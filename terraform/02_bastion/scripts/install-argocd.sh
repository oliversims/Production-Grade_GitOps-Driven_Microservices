#!/bin/bash
set -e

# Install ArgoCD (GitOps controller for the cluster).
#
# Run AFTER install-external-dns.sh (called by run-setup.sh).
# External DNS must be running first so argocd.oliver14.com gets a DNS record.
#
# Usage:
#   /opt/bastion/install-argocd.sh

# These variables store file paths used throughout this script.
# Instead of typing the full path every time, we define them once here and reuse them.
# Example: $VALUES_FILE expands to → /home/ubuntu/Production-Grade_GitOps-
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
ARGOCD_DIR="$REPO_DIR/argocd"
GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
VALUES_FILE="$ARGOCD_DIR/argocd-values-9.4.0.yaml"
TARGET_GROUP_FILE="$ARGOCD_DIR/target-grp-config.yaml"

echo "=== ArgoCD install ==="

# Step 1: Get ArgoCD config files from GitHub
echo "--- Step 1: Get ArgoCD files from GitHub ---"
cd "$HOME"

if [ -f "$VALUES_FILE" ]; then
  echo "ArgoCD files already exist."
elif [ -d "$REPO_DIR" ]; then
  echo "Adding argocd folder to existing repo..."
  cd "$REPO_DIR"
  git sparse-checkout add argocd
  git pull
else
  git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL"
  cd "$REPO_DIR"
  git sparse-checkout set argocd
fi

# Step 2: Add the ArgoCD Helm chart repo
echo "--- Step 2: Add Helm repo ---"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

# Step 3: Create the argocd namespace
echo "--- Step 3: Create namespace ---"
kubectl create namespace argocd 2>/dev/null || echo "Namespace argocd already exists."

# Step 4: Install ArgoCD with Helm
# Uses our values file: HTTPRoute on argocd.oliver14.com, insecure mode (TLS at ALB)
echo "--- Step 4: Install ArgoCD with Helm ---"
helm upgrade -i argo-cd argo/argo-cd \
  -f "$VALUES_FILE" \
  -n argocd \
  --version 9.4.0 \
  --create-namespace

# Step 5: Apply TargetGroupConfiguration
# Tells the AWS Load Balancer to route traffic directly to ArgoCD pod IPs
echo "--- Step 5: Apply TargetGroupConfiguration ---"
kubectl apply -f "$TARGET_GROUP_FILE"

# Step 6: Wait for ArgoCD server to be ready
echo "--- Step 6: Verify ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=300s
kubectl get pods -n argocd

echo ""
echo "=== ArgoCD install finished ==="
echo ""
echo "UI:      https://argocd.oliver14.com"
echo "User:    admin"
echo "Password (run this command to get it):"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
