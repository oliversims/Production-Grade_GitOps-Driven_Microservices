#!/bin/bash
set -e

# Deploy the boutique app via ArgoCD.
# Run AFTER install-argocd.sh / run-setup.sh.
#
# Prerequisites: GHCR_PAT env var or ~/.ghcr_pat (classic PAT with read:packages)
#
# Usage:
#   export GHCR_PAT="ghp_..."
#   /opt/bastion/apply-boutique-app.sh

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
APP_FILE="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"
GITHUB_REPO_URL="git@github.com:oliversims/Production-Grade_GitOps-Driven_Microservices.git"
SSH_KEY="$HOME/.ssh/id_ed25519"
GHCR_OWNER="${GHCR_OWNER:-oliversims}"
GHCR_HELM_URL="oci://ghcr.io/${GHCR_OWNER}"
GHCR_PAT_FILE="$HOME/.ghcr_pat"

echo "=== Deploy boutique app via ArgoCD ==="

# Step 1: Sparse-clone argocd/ folder from GitHub
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

# Step 3: Give ArgoCD SSH access to the private Git repo
echo "--- Step 3: Register GitHub repo credentials with ArgoCD ---"
if [ ! -f "$SSH_KEY" ]; then
  echo "ERROR: GitHub SSH key not found at $SSH_KEY"
  exit 1
fi

kubectl create secret generic github-repo-creds -n argocd \
  --from-literal=type=git \
  --from-literal=url="$GITHUB_REPO_URL" \
  --from-file=sshPrivateKey="$SSH_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret github-repo-creds -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite

# Step 4: Give ArgoCD access to pull the Helm chart from private GHCR
echo "--- Step 4: Register GHCR Helm credentials with ArgoCD ---"
if [ -z "$GHCR_PAT" ] && [ -f "$GHCR_PAT_FILE" ]; then
  GHCR_PAT=$(cat "$GHCR_PAT_FILE")
fi

if [ -z "$GHCR_PAT" ]; then
  echo "ERROR: GHCR_PAT is not set."
  echo "  export GHCR_PAT=\"ghp_...\"   # or: echo \"ghp_...\" > ~/.ghcr_pat && chmod 600 ~/.ghcr_pat"
  exit 1
fi

kubectl create secret generic ghcr-helm-creds -n argocd \
  --from-literal=type=helm \
  --from-literal=url="$GHCR_HELM_URL" \
  --from-literal=name=ghcr-helm \
  --from-literal=enableOCI=true \
  --from-literal=username="$GHCR_OWNER" \
  --from-literal=password="$GHCR_PAT" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret ghcr-helm-creds -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite

# Step 5: Wait for ArgoCD server
echo "--- Step 5: Check ArgoCD is ready ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=60s

# Step 6: Apply the ArgoCD Application (triggers sync of kustomization.yaml)
echo "--- Step 6: Apply boutique-app Application ---"
kubectl apply -f "$APP_FILE"

# Step 7: Show status
echo "--- Step 7: Status ---"
kubectl get application boutique-app -n argocd

echo ""
echo "=== Done ==="
echo "Watch: kubectl get application boutique-app -n argocd -w"
echo "UI:    https://argocd.oliver14.com"
echo "App:   https://app.oliver14.com  (~5 min after sync + DNS)"
echo ""
