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
#   3. Registers GitHub SSH credentials with ArgoCD (private Git repo)
#   4. Registers GHCR credentials with ArgoCD (private Helm chart on GHCR)
#   5. Applies the ArgoCD Application — ArgoCD syncs kustomization.yaml
#
# Prerequisites:
#   - GitHub deploy key on the bastion (~/.ssh/id_ed25519) — created by user_data
#   - GHCR_PAT env var OR ~/.ghcr_pat file (GitHub classic PAT with read:packages)
#
# Usage:
#   export GHCR_PAT="ghp_..."          # first run, or after bastion recreate
#   /opt/bastion/apply-boutique-app.sh
#
# Optional — save PAT so it survives bastion reboot (same instance):
#   echo "ghp_..." > ~/.ghcr_pat && chmod 600 ~/.ghcr_pat
#
# To update this script from a private repo (raw.githubusercontent.com returns 404):
#   cd ~/Production-Grade_GitOps-Driven_Microservices && git pull
#   sudo cp terraform/02_bastion/scripts/apply-boutique-app.sh /opt/bastion/
#   sudo chmod +x /opt/bastion/apply-boutique-app.sh

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

GHCR_OWNER="${GHCR_OWNER:-oliversims}"
# ↑ GitHub username / GHCR namespace (override with: export GHCR_OWNER=other-user)

GHCR_HELM_URL="oci://ghcr.io/${GHCR_OWNER}"
# ↑ Must match the repo field in kustomization.yaml helmCharts section

GHCR_PAT_FILE="$HOME/.ghcr_pat"
# ↑ Optional file to store PAT across bastion reboots (chmod 600)

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
# Step 4: Register GHCR Helm credentials with ArgoCD
# -------------------------------------------------------
# kustomization.yaml pulls the onlineboutique chart from private GHCR:
#   repo: oci://ghcr.io/oliversims
# Without this secret, ArgoCD fails with:
#   "ghcr.io/.../onlineboutique: 401 unauthorized"
#
# ArgoCD repo-server runs "helm pull" during kustomize build — it needs OCI registry auth.
echo "--- Step 4: Register GHCR Helm credentials with ArgoCD ---"

# Load PAT from env var, or from ~/.ghcr_pat if the file exists
if [ -z "$GHCR_PAT" ] && [ -f "$GHCR_PAT_FILE" ]; then
  GHCR_PAT=$(cat "$GHCR_PAT_FILE")
fi

if [ -z "$GHCR_PAT" ]; then
  echo "ERROR: GHCR_PAT is not set."
  echo ""
  echo "Create a GitHub classic PAT with read:packages scope, then either:"
  echo "  export GHCR_PAT=\"ghp_...\""
  echo "  /opt/bastion/apply-boutique-app.sh"
  echo ""
  echo "Or save it once (survives bastion reboot on the same instance):"
  echo "  echo \"ghp_...\" > ~/.ghcr_pat && chmod 600 ~/.ghcr_pat"
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

# -------------------------------------------------------
# Step 5: Make sure ArgoCD is running
# -------------------------------------------------------
# Wait until the ArgoCD API server pod is ready before applying the Application.
echo "--- Step 5: Check ArgoCD is ready ---"
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=60s

# -------------------------------------------------------
# Step 6: Apply the ArgoCD Application
# -------------------------------------------------------
# This creates the boutique-app resource in the argocd namespace.
# ArgoCD sees it, clones the repo (SSH secret from Step 3),
# runs kustomize build with helmCharts (GHCR secret from Step 4),
# and deploys everything to the boutique-app namespace.
echo "--- Step 6: Apply boutique-app Application ---"
kubectl apply -f "$APP_FILE"

# -------------------------------------------------------
# Step 7: Show status
# -------------------------------------------------------
# SYNC STATUS / HEALTH may show Progressing until ArgoCD finishes the first sync.
echo "--- Step 7: Status ---"
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
