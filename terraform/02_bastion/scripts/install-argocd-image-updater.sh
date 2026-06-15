#!/bin/bash
set -e

# Install Argo CD Image Updater and apply the boutique ImageUpdater CR.
# Public GitHub repo + public GHCR packages — no credentials required.
#
# Run AFTER install-argocd.sh (run-app-monitoring-setup.sh step 1).
# Run BEFORE apply-boutique-app.sh.
#
# Usage:
#   /opt/bastion/install-argocd-image-updater.sh

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
ARGOCD_DIR="$REPO_DIR/argocd"
GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
VALUES_FILE="$ARGOCD_DIR/argo-image-updater-values-1.0.5.yaml"
IMAGE_UPDATER_CR="$ARGOCD_DIR/image-updater.yaml"

echo "=== Argo CD Image Updater install ==="

# Step 1: Get config files from GitHub
echo "--- Step 1: Get Image Updater files from GitHub ---"
cd "$HOME"

# Clone if missing; ignore error if repo already exists
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true

cd "$REPO_DIR"
# Add argocd folder if sparse checkout already exists; otherwise init it
git sparse-checkout add argocd 2>/dev/null || git sparse-checkout set argocd
git pull

# Step 2: Install with Helm
echo "--- Step 2: Install Image Updater with Helm ---"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

helm upgrade -i argocd-image-updater argo/argocd-image-updater \
  -f "$VALUES_FILE" \
  -n argocd \
  --version 1.0.5

# Step 3: Apply ImageUpdater CR (watches boutique-* apps in GHCR)
echo "--- Step 3: Apply ImageUpdater CR ---"
kubectl apply -f "$IMAGE_UPDATER_CR"

# Step 4: Verify
echo "--- Step 4: Verify ---"
kubectl rollout status deployment/argocd-image-updater-controller -n argocd --timeout=300s
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater

echo ""
echo "=== Argo CD Image Updater install finished ==="
echo ""
echo "Next: /opt/bastion/apply-boutique-app.sh"
echo ""
