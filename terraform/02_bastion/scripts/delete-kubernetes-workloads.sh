#!/bin/bash
set -euo pipefail

# Tear down everything installed by run-setup.sh, in reverse order (step 7 → 1).
# Prerequisite: delete boutique-app in Argo CD UI first.
# Run BEFORE: terraform destroy (03_eks → 02_bastion → 01_vpc)
#
# Usage: /opt/bastion/delete-kubernetes-workloads.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
MANIFESTS_DIR="$REPO_DIR/gateway-api-manifests"
ARGOCD_TARGET_GRP="$REPO_DIR/argocd/target-grp-config.yaml"
IMAGE_UPDATER_CR="$REPO_DIR/argocd/image-updater.yaml"

# Poll until a resource is gone. Skips if already deleted. Default timeout: 3 min.
wait_for_delete() {
  local resource="$1"
  local namespace="${2:-}"
  local timeout="${3:-180s}"

  kubectl get ${namespace:+-n "$namespace"} "$resource" >/dev/null 2>&1 || {
    echo "$resource already gone."
    return
  }

  echo "Waiting for $resource to be fully removed..."
  kubectl wait ${namespace:+-n "$namespace"} --for=delete "$resource" --timeout="$timeout" \
    || echo "WARNING: Timed out waiting for $resource to be deleted."
}

# helm uninstall + wait for its deployment to disappear.
helm_uninstall_and_wait() {
  local release="$1"
  local namespace="$2"
  local deployment="$3"
  local timeout="${4:-180s}"

  helm uninstall "$release" -n "$namespace" 2>/dev/null || true
  wait_for_delete "deployment/$deployment" "$namespace" "$timeout"
}

echo ""
echo "========================================"
echo "  Kubernetes teardown started"
echo "  (reverse of run-setup.sh, step 7 → 1)"
echo "========================================"
echo ""

# Connect kubectl to the EKS cluster.
/opt/bastion/configure-kubeconfig.sh

# Pull delete manifests from GitHub (argocd + gateway-api-manifests folders).
cd "$HOME"
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"
git sparse-checkout add argocd 2>/dev/null || git sparse-checkout set argocd
git sparse-checkout add gateway-api-manifests 2>/dev/null || true
git pull

# -------------------------------------------------------
# Step 7 (reverse): Argo CD Image Updater
# Watches GHCR for new images — remove before Argo CD itself.
# -------------------------------------------------------
echo "Reverse step 7: Delete Argo CD Image Updater"
echo ""

kubectl delete -f "$IMAGE_UPDATER_CR" --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "imageupdater/boutique-image-updater" "argocd" "120s"

helm_uninstall_and_wait "argocd-image-updater" "argocd" "argocd-image-updater-controller" 180s

echo "Argo CD Image Updater removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 6 (reverse): Argo CD
# GitOps controller — remove routing config, then Helm release, then namespace.
# -------------------------------------------------------
echo "Reverse step 6: Delete ArgoCD"
echo ""

# Detach Argo CD from the shared ALB before uninstalling.
kubectl delete -f "$ARGOCD_TARGET_GRP" --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "targetgroupconfiguration/argo-tg-config" "argocd" "120s"

helm_uninstall_and_wait "argo-cd" "argocd" "argo-cd-argocd-server" 180s

kubectl delete namespace argocd --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/argocd" "" "600s"

echo "ArgoCD removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 5 (reverse): External DNS
# Manages Route53 records — remove app before tearing down ingress.
# -------------------------------------------------------
echo "Reverse step 5: Delete External DNS"
echo ""

helm_uninstall_and_wait "external-dns" "external-dns" "external-dns" 180s

kubectl delete namespace external-dns --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/external-dns" "" "600s"

# Revoke AWS Pod Identity (Route53 permissions).
eksctl delete podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --region="$REGION" \
  --wait 2>/dev/null || true

echo "External DNS removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 4 (reverse): Gateway / ALB
# HTTPRoutes first, then Gateway (triggers ALB delete), then config/class.
# -------------------------------------------------------
echo "Reverse step 4: Delete gateway manifests"
echo ""

kubectl delete httproute --all -A --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

# Deleting the Gateway tells AWS to remove the internet-facing ALB (slow — up to 10 min).
kubectl delete -f "$MANIFESTS_DIR/gateway.yaml" --ignore-not-found --wait=true --timeout=600s 2>/dev/null || true
wait_for_delete "gateway/app-alb-gateway" "default" "600s"

kubectl delete -f "$MANIFESTS_DIR/alb-config.yaml" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "loadbalancerconfiguration/app-gw-lbconfig" "default" "120s"

kubectl delete -f "$MANIFESTS_DIR/gateway-class.yaml" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "gatewayclass/aws-alb-gateway-class" "" "120s"

echo "Gateway manifests removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 3 (reverse): Gateway API CRDs
# Custom resource definitions — safe to remove once all Gateway objects are gone.
# -------------------------------------------------------
echo "Reverse step 3: Delete Gateway API CRDs"
echo ""

kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

echo "Gateway API CRDs removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 2 (reverse): AWS Load Balancer Controller
# Controller that manages ALBs — remove last among platform components.
# -------------------------------------------------------
echo "Reverse step 2: Delete AWS Load Balancer Controller"
echo ""

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
wait_for_delete "deployment/aws-load-balancer-controller" "kube-system" "600s"

# Revoke IAM role (IRSA) used by the controller.
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region="$REGION" \
  --wait 2>/dev/null || true

kubectl delete -f https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

kubectl delete priorityclass system-cluster-critical --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "priorityclass/system-cluster-critical" "" "60s"

echo "Load Balancer Controller removed."
echo ""
echo "----------------------------------------"
echo ""

# Step 1 (reverse): configure-kubeconfig — no resources to delete.
echo "Reverse step 1: configure-kubeconfig (no cluster resources to delete)"
echo ""

# Node ENIs stay until the EKS cluster itself is destroyed.
echo "NOTE: Node ENIs will clear when you destroy the EKS cluster."

echo ""
echo "========================================"
echo "  Kubernetes teardown finished"
echo "========================================"
echo ""
echo "Next: terraform destroy in 03_eks, then 02_bastion, then 01_vpc"
echo ""
