#!/bin/bash
set -e

# Clone gateway-api-manifests from GitHub and apply the manifests.
# Run AFTER install-gateway-api-crds.sh (called by run-platform-setup.sh).
#
# Usage:
#   /opt/bastion/apply-gateway-manifests.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
MANIFESTS_DIR="$REPO_DIR/gateway-api-manifests"

echo "=== Gateway manifests setup started ==="

# Step 1: Clone only the gateway-api-manifests folder from GitHub
echo "--- Step 1: Clone gateway-api-manifests ---"
cd "$HOME"

# Clone if missing; ignore error if repo already exists
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"

# Add gateway-api-manifests folder if sparse checkout already exists; otherwise init it
git sparse-checkout add gateway-api-manifests 2>/dev/null || git sparse-checkout set gateway-api-manifests
git pull

# Step 2: Apply all manifest files
echo "--- Step 2: Apply manifests ---"
kubectl apply -f "$MANIFESTS_DIR/gateway-class.yaml"
kubectl apply -f "$MANIFESTS_DIR/alb-config.yaml"
kubectl apply -f "$MANIFESTS_DIR/gateway.yaml"

# Step 3: Verify all resources were created
echo "--- Step 3: Verify manifests ---"
kubectl get gatewayclass aws-alb-gateway-class
kubectl get loadbalancerconfiguration app-gw-lbconfig -n default
kubectl get gateway app-alb-gateway -n default
kubectl get gateway app-alb-gateway -n default -o jsonpath='{.status.conditions[*].type}'
echo ""

echo "=== Gateway manifests setup finished ==="
