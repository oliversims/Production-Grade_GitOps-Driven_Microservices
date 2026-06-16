#!/bin/bash
set -e

# Apply HorizontalPodAutoscaler manifests for the boutique app.
# Run AFTER install-metrics-server.sh (metrics-server must be running).
# README: Scaling & Reliability — STEP 2 and STEP 3.
#
# Usage:
#   /opt/bastion/apply-hpa.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
SCALING_DIR="$REPO_DIR/scaling"
APP_NAMESPACE="boutique-app"

echo "=== Apply HPA manifests ==="

# Step 1: Get scaling manifests from GitHub
echo "--- Step 1: Get scaling manifests from GitHub ---"
cd "$HOME"

# Clone if missing; ignore error if repo already exists
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"

# Add scaling folder if sparse checkout already exists; otherwise init it
git sparse-checkout add scaling 2>/dev/null || git sparse-checkout set scaling
git pull

# Step 2: Connect kubectl to the EKS cluster
echo "--- Step 2: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 3: Verify metrics-server is ready (HPA needs it for CPU metrics)
echo "--- Step 3: Verify metrics-server ---"
kubectl rollout status deployment/metrics-server -n kube-system --timeout=60s

# Step 4: Verify CPU requests are set on frontend (HPA requires requests)
echo "--- Step 4: Verify CPU requests on frontend ---"
kubectl get deploy frontend -n "$APP_NAMESPACE" -o yaml | grep -A10 resources

# Step 5: Apply HPA manifests
echo "--- Step 5: Apply HPA manifests ---"
kubectl apply -f "$SCALING_DIR/"

# Step 6: Verify HPAs
echo "--- Step 6: Verify ---"
kubectl get hpa -n "$APP_NAMESPACE"
kubectl get deploy frontend -n "$APP_NAMESPACE"

echo ""
echo "=== HPA apply finished ==="
echo ""
echo "Check HPA status:"
echo "  kubectl get hpa -n boutique-app"
echo "  kubectl describe hpa frontend-hpa -n boutique-app"
echo ""
echo "Watch frontend scale under load:"
echo "  kubectl get pods -n boutique-app -l app=frontend -w"
echo ""
