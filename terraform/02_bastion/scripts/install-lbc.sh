#!/bin/bash
set -e

# Install AWS Load Balancer Controller (LBC).
#
# Run this AFTER configure-kubeconfig.sh.
# Run as the ubuntu user (not sudo) — kubectl needs /home/ubuntu/.kube/config.
#
# OIDC provider is already created by Terraform (03_eks enable_irsa = true).
#
# Usage:
#   /opt/bastion/install-lbc.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_FILE="/opt/bastion/aws-load-balancer-controller-iam-policy.json"

echo "=== AWS Load Balancer Controller install ==="

# Step 1: Make sure kubectl can reach the cluster
echo "--- Step 1: Check cluster access ---"
kubectl get nodes

# Step 2: Get AWS account ID and VPC ID (needed for IAM and Helm)
echo "--- Step 2: Get account ID and VPC ID ---"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
echo "Account ID: $ACCOUNT_ID"
echo "VPC ID: $VPC_ID"

# Step 3: Create or update the IAM policy
# Policy JSON is copied to /opt/bastion/ by bastion setup (user_data.sh.tpl).
# The policy stays in your AWS account even after you destroy the cluster.
echo "--- Step 3: Create or update IAM policy ---"

# First run: create the policy. Re-apply: skip quietly (same pattern as install-external-dns.sh).
aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "file://${POLICY_FILE}" \
  2>/dev/null || echo "IAM policy already exists, using $POLICY_ARN"

# Always publish the bundled policy as the default version so permissions stay current
# (needed after destroy/reapply when an older policy version is still in AWS).
aws iam create-policy-version \
  --policy-arn "$POLICY_ARN" \
  --policy-document "file://${POLICY_FILE}" \
  --set-as-default

# Step 4: Create the Kubernetes service account with an IAM role (IRSA)
echo "--- Step 4: Create service account with IAM role ---"

# 4a: Clean up leftovers from a previous install (does nothing on a fresh cluster)
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region "$REGION" \
  --wait 2>/dev/null || true
kubectl delete sa aws-load-balancer-controller -n kube-system 2>/dev/null || true
echo "Waiting 30 seconds for cleanup..."
sleep 30

# 4b: Create the service account and attach the IAM policy
eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="$POLICY_ARN" \
  --override-existing-serviceaccounts \
  --region "$REGION" \
  --approve
kubectl get sa aws-load-balancer-controller -n kube-system

# Step 5: Remove a broken deployment from a previous run (does nothing on a fresh cluster)
echo "--- Step 5: Remove old deployment (if any) ---"
kubectl delete deployment aws-load-balancer-controller -n kube-system 2>/dev/null || true

# Step 6: Install the Custom Resource Definitions the controller needs
echo "--- Step 6: Apply CRDs ---"
kubectl apply -f https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml

# Step 7: Create a priority class so controller pods schedule reliably
echo "--- Step 7: Create priority class ---"
kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: system-cluster-critical
value: 2000000000
globalDefault: false
description: "For cluster critical pods"
EOF

# Step 8: Add the AWS Helm chart repository
echo "--- Step 8: Add Helm repo ---"
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# Step 9: Install the controller with Helm
# ALB Gateway API only — NLBGatewayAPI requires experimental TCPRoute/TLSRoute/UDPRoute CRDs
echo "--- Step 9: Install controller ---"
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set controllerConfig.featureGates.ALBGatewayAPI=true \
  --version 3.0.0

# Step 10: Wait until both controller pods are running
echo "--- Step 10: Wait for pods ---"
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s

# Step 11: Show the final result
echo "--- Step 11: Show result ---"
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

echo "=== Done ==="
