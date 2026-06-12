#!/bin/bash
set -e

# Deploy the boutique app via ArgoCD.
#
# Run this AFTER ArgoCD is installed (install-argocd.sh / run-setup.sh).
# This creates the ArgoCD Application, which tells ArgoCD to sync
# kustomization.yaml from Git and deploy the boutique microservices.
#
# Usage:
#   /opt/bastion/apply-boutique-app.sh

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
APP_FILE="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"

echo "=== Deploy boutique app via ArgoCD ==="

# Step 1: Get boutique-app.yaml from GitHub
echo "--- Step 1: Get Application manifest from GitHub ---"
cd "$HOME"

if [ -f "$APP_FILE" ]; then
  echo "Application manifest already exists."
elif [ -d "$REPO_DIR" ]; then
  echo "Adding argocd folder to existing repo..."
  cd "$REPO_DIR"
  git sparse-checkout add argocd
  git pull
else
  git clone --filter=blob:none --sparse -b main git@github.com:oliversims/Production-Grade_GitOps-Driven_Microservices.git
  cd "$REPO_DIR"
  git sparse-checkout set argocd
fi

# Step 2: Make sure ArgoCD is running
echo "--- Step 2: Check ArgoCD is ready ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=60s

# Step 3: Apply the ArgoCD Application
echo "--- Step 3: Apply boutique-app Application ---"
kubectl apply -f "$APP_FILE"

# Step 4: Show status
echo "--- Step 4: Status ---"
kubectl get application boutique-app -n argocd

echo ""
echo "=== Done ==="
echo ""
echo "ArgoCD will now sync from Git using kustomization.yaml at the repo root."
echo "Watch progress:"
echo "  kubectl get application boutique-app -n argocd -w"
echo ""
echo "UI:  https://argocd.oliver14.com"
echo "App: https://app.oliver14.com  (after sync + DNS propagate, ~5 min)"
echo ""
