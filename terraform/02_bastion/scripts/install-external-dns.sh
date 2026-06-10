#!/bin/bash
set -e

# Install External DNS (updates Route53 records for Gateway/Ingress).
#
# Run AFTER apply-gateway-manifests.sh (called by run-setup.sh).
# Uses EKS Pod Identity (eks-pod-identity-agent addon from 03_eks).
#
# Usage:
#   /opt/bastion/install-external-dns.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
VALUES_FILE="$REPO_DIR/external-dns/external-dns-values-1.20.0.yaml"

echo "=== External DNS install ==="

# Step 1: Get the Helm values file from GitHub
echo "--- Step 1: Get Helm values file ---"
cd "$HOME"

if [ -f "$VALUES_FILE" ]; then
  echo "Values file already exists."
elif [ -d "$REPO_DIR" ]; then
  echo "Adding external-dns folder to existing repo..."
  cd "$REPO_DIR"
  git sparse-checkout add external-dns
  git pull
else
  git clone --filter=blob:none --sparse -b main git@github.com:oliversims/Production-Grade_GitOps-Driven_Microservices.git
  cd "$REPO_DIR"
  git sparse-checkout set external-dns
fi

# Step 2: Create IAM policy for Route53 (skip if it already exists)
echo "--- Step 2: Create IAM policy ---"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AllowExternalDNSUpdates"

if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "IAM policy already exists, using $POLICY_ARN"
else
  cat > /tmp/external-dns-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResources"
      ],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["route53:ListHostedZones"],
      "Resource": ["*"]
    }
  ]
}
EOF
  aws iam create-policy \
    --policy-name AllowExternalDNSUpdates \
    --policy-document file:///tmp/external-dns-policy.json
fi

# Step 3: Create namespace for External DNS
echo "--- Step 3: Create namespace ---"
kubectl create namespace external-dns 2>/dev/null || echo "Namespace external-dns already exists."

# Step 4: Link the service account to the IAM policy (Pod Identity)
echo "--- Step 4: Create Pod Identity association ---"
eksctl delete podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --region="$REGION" 2>/dev/null || true

eksctl create podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --role-name=external-dns-pod-identity-role \
  --permission-policy-arns="$POLICY_ARN" \
  --region="$REGION"

# Step 5: Install External DNS with Helm
echo "--- Step 5: Install External DNS ---"
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
helm repo update external-dns

helm upgrade -i external-dns external-dns/external-dns \
  -f "$VALUES_FILE" \
  -n external-dns \
  --version 1.20.0

# Step 6: Verify the pod is running
echo "--- Step 6: Verify ---"
kubectl rollout status deployment/external-dns -n external-dns --timeout=300s
kubectl get pods -n external-dns

echo "=== External DNS install finished ==="
