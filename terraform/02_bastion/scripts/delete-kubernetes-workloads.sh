#!/bin/bash
set -e

# Remove Kubernetes workloads BEFORE terraform destroy.
# Run on the bastion as the ubuntu user (needs kubeconfig).
#
# Teardown order (reverse of run-setup.sh):
#   1. Boutique app (ArgoCD-managed workloads)
#   2. ArgoCD
#   3. External DNS
#   4. Gateway API + AWS ALB
#   5. AWS Load Balancer Controller
#   6. Wait for AWS ENIs to clear (needed for VPC destroy)
#
# Usage:
#   /opt/bastion/delete-kubernetes-workloads.sh
#
# Then:
#   terraform destroy in 03_eks, then 02_bastion, then 01_vpc

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
MANIFESTS_DIR="$REPO_DIR/gateway-api-manifests"
ARGOCD_TARGET_GRP="$REPO_DIR/argocd/target-grp-config.yaml"

MAX_WAIT_LOOPS=60   # 60 x 10s = 10 minutes max per wait step

echo ""
echo "========================================"
echo "  Kubernetes teardown started"
echo "========================================"
echo ""

# Step 1: Connect kubectl to the cluster
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

# Step 2: Remove the boutique app (if deployed via ArgoCD)
echo "Step 2: Delete boutique app"
echo ""

echo "Removing ArgoCD Application (stops GitOps sync)..."
kubectl delete application boutique-app -n argocd --ignore-not-found --wait=true --timeout=300s

echo "Removing image updater config (if present)..."
kubectl delete imageupdaters boutique-image-updater -n argocd --ignore-not-found 2>/dev/null || true

echo "Removing boutique-app namespace (app pods, HTTPRoute, TargetGroupConfiguration)..."
kubectl delete namespace boutique-app --ignore-not-found --wait=true --timeout=300s

echo "Boutique app removed."

echo ""
echo "----------------------------------------"
echo ""

# Step 3: Remove ArgoCD
echo "Step 3: Delete ArgoCD"
echo ""

if [ -f "$ARGOCD_TARGET_GRP" ]; then
  echo "Removing ArgoCD TargetGroupConfiguration..."
  kubectl delete -f "$ARGOCD_TARGET_GRP" --ignore-not-found --timeout=60s 2>/dev/null || true
else
  echo "ArgoCD target group file not found, skipping file delete."
fi

echo "Uninstalling ArgoCD Helm release..."
helm uninstall argo-cd -n argocd 2>/dev/null || true

echo "Removing argocd namespace..."
kubectl delete namespace argocd --ignore-not-found --wait=true --timeout=300s

echo "ArgoCD removed."

echo ""
echo "----------------------------------------"
echo ""

# Step 4: Remove External DNS
echo "Step 4: Delete External DNS"
echo ""

helm uninstall external-dns -n external-dns 2>/dev/null || true

echo "Removing external-dns namespace..."
kubectl delete namespace external-dns --ignore-not-found --wait=true --timeout=300s

echo "Removing External DNS Pod Identity association..."
eksctl delete podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --region="$REGION" 2>/dev/null || true

echo "External DNS removed."

echo ""
echo "----------------------------------------"
echo ""

# Step 5: Remove Gateway API resources and the AWS ALB
echo "Step 5: Delete gateway manifests"
echo ""

echo "Removing all HTTPRoutes (any namespace)..."
kubectl delete httproute --all -A --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true

if [ -f "$MANIFESTS_DIR/gateway.yaml" ]; then
  echo "Removing Gateway (this deletes the AWS ALB)..."
  kubectl delete -f "$MANIFESTS_DIR/gateway.yaml" --ignore-not-found --timeout=120s 2>/dev/null || true
else
  echo "gateway.yaml not found, skipping."
fi

echo "Waiting for AWS load balancers in the VPC to be removed..."
TRIES=0
while [ "$(aws elbv2 describe-load-balancers \
  --query "length(LoadBalancers[?VpcId=='${VPC_ID}'])" \
  --output text)" != "0" ]; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$MAX_WAIT_LOOPS" ]; then
    echo "WARNING: Timed out waiting for load balancers. Check AWS console, then retry."
    break
  fi
  sleep 10
done
echo "Load balancer wait finished."

if [ -f "$MANIFESTS_DIR/alb-config.yaml" ]; then
  echo "Removing LoadBalancerConfiguration..."
  kubectl delete -f "$MANIFESTS_DIR/alb-config.yaml" --ignore-not-found --timeout=60s 2>/dev/null || true
fi

if [ -f "$MANIFESTS_DIR/gateway-class.yaml" ]; then
  echo "Removing GatewayClass..."
  kubectl delete -f "$MANIFESTS_DIR/gateway-class.yaml" --ignore-not-found --timeout=60s 2>/dev/null || true
fi

echo "Gateway manifests removed."

echo ""
echo "----------------------------------------"
echo ""

# Step 6: Remove AWS Load Balancer Controller
echo "Step 6: Delete AWS Load Balancer Controller"
echo ""

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

echo "Waiting for controller deployment to be removed..."
TRIES=0
while kubectl get deployment aws-load-balancer-controller -n kube-system >/dev/null 2>&1; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$MAX_WAIT_LOOPS" ]; then
    echo "WARNING: Timed out waiting for controller deployment."
    break
  fi
  sleep 10
done

echo "Removing Load Balancer Controller IAM service account..."
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region="$REGION" \
  --wait 2>/dev/null || true

echo "Load Balancer Controller removed."

echo ""
echo "----------------------------------------"
echo ""

# Step 7: Wait for leftover ENIs to clear (blocks VPC/subnet destroy if still attached)
echo "Step 7: Wait for AWS ENIs to be removed"
echo ""

TRIES=0
while [ "$(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "length(NetworkInterfaces)" \
  --output text)" != "0" ]; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$MAX_WAIT_LOOPS" ]; then
    echo "WARNING: Timed out waiting for ENIs. Check AWS console, then retry."
    break
  fi
  sleep 10
done
echo "ENI wait finished."

echo ""
echo "========================================"
echo "  Kubernetes teardown finished"
echo "========================================"
echo ""
echo "Next: terraform destroy in 03_eks, then 02_bastion, then 01_vpc"
echo ""
