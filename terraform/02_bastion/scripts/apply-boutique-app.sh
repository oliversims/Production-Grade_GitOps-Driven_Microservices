#!/bin/bash
set -e

# Deploy the boutique app via ArgoCD.
# Run AFTER install-argocd.sh / run-setup.sh.
#
# Easiest setup (no tokens in this script):
#   1. GitHub repo → Settings → change visibility to Public
#   2. GHCR packages → Package settings → Change visibility to Public
#      (onlineboutique chart + microservices-demo images)
#
# Usage:
#   /opt/bastion/apply-boutique-app.sh

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
APP_FILE="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"
GITHUB_REPO_URL="git@github.com:oliversims/Production-Grade_GitOps-Driven_Microservices.git"

echo "=== Deploy boutique app via ArgoCD ==="

# Step 1: Get boutique-app.yaml from GitHub
echo "--- Step 1: Get Application manifest from GitHub ---"
cd "$HOME"

if [ -f "$APP_FILE" ]; then
  echo "Application manifest already exists — pulling latest..."
  cd "$REPO_DIR"
  git pull
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

# Step 2: Connect kubectl to EKS
echo "--- Step 2: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 3: Wait for ArgoCD server
echo "--- Step 3: Check ArgoCD is ready ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=60s

# Step 4: Apply the ArgoCD Application
echo "--- Step 4: Apply boutique-app Application ---"
kubectl apply -f "$APP_FILE"

# Step 5: Show status
echo "--- Step 5: Status ---"
kubectl get application boutique-app -n argocd

echo ""
echo "=== Done ==="
echo "Watch: kubectl get application boutique-app -n argocd -w"
echo "UI:    https://argocd.oliver14.com"
echo "App:   https://app.oliver14.com  (~5 min after sync + DNS)"
echo ""
