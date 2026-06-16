#!/bin/bash
set -e

# Deploy the boutique app via ArgoCD.
# Run AFTER install-argocd.sh / run-platform-setup.sh.
#
# Requires public GitHub repo + public GHCR packages (no credentials needed).
#
# Usage:
#   /opt/bastion/apply-boutique-app.sh

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
APP_FILE="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"
GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

echo "=== Deploy boutique app via ArgoCD ==="

# Step 1: Get Application manifest from GitHub
echo "--- Step 1: Get Application manifest from GitHub ---"
cd "$HOME"

# Clone if missing; ignore error if repo already exists
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"

# Add argocd folder if sparse checkout already exists; otherwise init it
git sparse-checkout add argocd 2>/dev/null || git sparse-checkout set argocd
git pull

# Step 2: Connect kubectl to EKS
echo "--- Step 2: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 3: Wait for ArgoCD server
echo "--- Step 3: Check ArgoCD is ready ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=60s

# Step 4: Apply the ArgoCD Application (triggers sync of kustomization.yaml)
echo "--- Step 4: Apply boutique-app Application ---"
kubectl apply -f "$APP_FILE"

# Step 5: Show status
echo "--- Step 5: Status ---"
kubectl get application boutique-app -n argocd
kubectl get namespace boutique-app
kubectl get pods -n boutique-app
kubectl get svc frontend -n boutique-app

echo ""
echo "=== Done ==="
echo "Watch: kubectl get application boutique-app -n argocd -w"
echo "UI:    https://argocd.oliver14.com"
echo "App:   https://app.oliver14.com  (~5 min after sync + DNS)"
echo ""
