#!/bin/bash
set -e

# Run BEFORE terraform destroy on 03_eks, 02_bastion, and 01_vpc.
#
# Usage:
#   /opt/bastion/delete-kubernetes-workloads.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
MANIFESTS_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices/gateway-api-manifests"

echo ""
echo "========================================"
echo "  Kubernetes teardown started"
echo "========================================"
echo ""

echo "Step 1: Configure kubeconfig"
echo ""
/opt/bastion/configure-kubeconfig.sh

VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo ""
echo "----------------------------------------"
echo ""

echo "Step 2: Delete External DNS"
echo ""

helm uninstall external-dns -n external-dns 2>/dev/null || true

echo "Waiting for External DNS namespace to be removed..."
kubectl delete namespace external-dns --ignore-not-found --wait=true --timeout=300s

eksctl delete podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --region="$REGION" 2>/dev/null || true

echo "External DNS removed."

echo ""
echo "----------------------------------------"
echo ""

echo "Step 3: Delete gateway manifests"
echo ""

echo "Deleting HTTPRoutes..."
kubectl delete httproute --all -A --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
echo "HTTPRoutes removed."

echo "Deleting Gateway (this removes the AWS ALB)..."
kubectl delete -f "$MANIFESTS_DIR/gateway.yaml" --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
echo "Gateway removed."

echo "Waiting for AWS load balancers to be removed..."
while [ "$(aws elbv2 describe-load-balancers \
  --query "length(LoadBalancers[?VpcId=='${VPC_ID}'])" \
  --output text)" != "0" ]; do
  sleep 10
done
echo "AWS load balancers removed."

echo "Deleting LoadBalancerConfiguration..."
kubectl delete -f "$MANIFESTS_DIR/alb-config.yaml" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
echo "LoadBalancerConfiguration removed."

echo "Deleting GatewayClass..."
kubectl delete -f "$MANIFESTS_DIR/gateway-class.yaml" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
echo "GatewayClass removed."

echo ""
echo "----------------------------------------"
echo ""

echo "Step 4: Delete AWS Load Balancer Controller"
echo ""

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

echo "Waiting for Load Balancer Controller to be removed..."
while kubectl get deployment aws-load-balancer-controller -n kube-system >/dev/null 2>&1; do
  sleep 10
done
echo "Load Balancer Controller removed."

echo ""
echo "----------------------------------------"
echo ""

echo "Step 5: Wait for AWS ENIs to be removed"
echo ""

while [ "$(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "length(NetworkInterfaces)" \
  --output text)" != "0" ]; do
  sleep 10
done
echo "AWS ENIs removed."

echo ""
echo "========================================"
echo "  Kubernetes teardown finished"
echo "========================================"
echo ""
echo "Next: terraform destroy in 03_eks, then 02_bastion, then 01_vpc"
echo ""
