#!/bin/bash
set -e

# -------------------------------------------------------
# Deploy the boutique app via ArgoCD (GitOps)
# -------------------------------------------------------
# Run this AFTER ArgoCD is installed (install-argocd.sh / run-setup.sh).
#
# What this script does:
#   1. Downloads boutique-app.yaml from your private GitHub repo
#   2. Connects kubectl to the EKS cluster
#   3. Gives ArgoCD the SSH key it needs to read the private repo
#   4. Registers the ArgoCD Application — ArgoCD then syncs kustomization.yaml
#
# Usage:
#   /opt/bastion/apply-boutique-app.sh

# -------------------------------------------------------
# VARIABLES: Paths and settings used throughout the script
# -------------------------------------------------------
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
# ↑ Local folder where we sparse-clone the GitHub repo

APP_FILE="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"
# ↑ The ArgoCD Application manifest — tells ArgoCD WHAT repo to watch and WHERE to deploy

GITHUB_REPO_URL="git@github.com:oliversims/Production-Grade_GitOps-Driven_Microservices.git"
# ↑ SSH URL for the private repo (must match repoURL in boutique-app.yaml)

SSH_KEY="$HOME/.ssh/id_ed25519"
# ↑ GitHub deploy key injected on bastion boot by user_data.sh.tpl
#   The same key is used for git clone on the bastion AND for ArgoCD repo access

echo "=== Deploy boutique app via ArgoCD ==="

# -------------------------------------------------------
# Step 1: Get boutique-app.yaml from GitHub
# -------------------------------------------------------
# We need the Application manifest on disk before kubectl apply.
# Sparse checkout downloads only the argocd/ folder (not the entire repo).
echo "--- Step 1: Get Application manifest from GitHub ---"
cd "$HOME"

if [ -f "$APP_FILE" ]; then
  # Manifest already cloned — pull latest in case boutique-app.yaml changed on GitHub
  echo "Application manifest already exists — pulling latest..."
  cd "$REPO_DIR"
  git pull
elif [ -d "$REPO_DIR" ]; then
  # Repo exists but argocd/ folder was not checked out yet
  echo "Adding argocd folder to existing repo..."
  cd "$REPO_DIR"
  git sparse-checkout add argocd
  git pull
else
  # First run — clone repo and check out only the argocd/ folder
  git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL"
  cd "$REPO_DIR"
  git sparse-checkout set argocd
fi

# -------------------------------------------------------
# Step 2: Connect kubectl to the EKS cluster
# -------------------------------------------------------
# Fresh bastions have no kubeconfig — kubectl would default to localhost:8080.
# configure-kubeconfig.sh runs: aws eks update-kubeconfig --name terraform-cluster
echo "--- Step 2: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# -------------------------------------------------------
# Step 3: Register GitHub SSH credentials with ArgoCD
# -------------------------------------------------------
# ArgoCD runs inside the cluster and must clone your private repo on its own.
# Without this secret, ArgoCD fails with:
#   "authentication required: Repository not found"
#
# We store the bastion deploy key in a Kubernetes Secret. ArgoCD discovers secrets
# labeled argocd.argoproj.io/secret-type=repository and uses them to authenticate.
echo "--- Step 3: Register GitHub repo credentials with ArgoCD ---"

if [ ! -f "$SSH_KEY" ]; then
  echo "ERROR: GitHub SSH key not found at $SSH_KEY"
  echo "       The key is created on bastion first boot via user_data."
  exit 1
fi

# Create or update the repo credential secret (idempotent — safe to re-run)
kubectl create secret generic github-repo-creds -n argocd \
  --from-literal=type=git \
  --from-literal=url="$GITHUB_REPO_URL" \
  --from-file=sshPrivateKey="$SSH_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Label tells ArgoCD this secret holds Git repository credentials
kubectl label secret github-repo-creds -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite

# -------------------------------------------------------
# Step 4: Make sure ArgoCD is running
# -------------------------------------------------------
# Wait until the ArgoCD API server pod is ready before applying the Application.
echo "--- Step 4: Check ArgoCD is ready ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=60s

# -------------------------------------------------------
# Step 5: Apply the ArgoCD Application
# -------------------------------------------------------
# This creates the boutique-app resource in the argocd namespace.
# ArgoCD sees it, clones the repo (using the SSH secret from Step 3),
# reads kustomization.yaml at the repo root, and deploys to boutique-app namespace.
echo "--- Step 5: Apply boutique-app Application ---"
kubectl apply -f "$APP_FILE"

# -------------------------------------------------------
# Step 6: Show status
# -------------------------------------------------------
# SYNC STATUS / HEALTH may show Progressing until ArgoCD finishes the first sync.
echo "--- Step 6: Status ---"
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
