#!/bin/bash
set -e

# Install metrics-server (required for HPA and kubectl top).
#
# Run AFTER run-app-monitoring-setup.sh (boutique-app must exist for pod metrics demo).
# README: Scaling & Reliability — STEP 1.
#
# Usage:
#   /opt/bastion/install-metrics-server.sh

NAMESPACE="kube-system"
RELEASE_NAME="metrics-server"
CHART_VERSION="3.13.0"

echo "=== metrics-server install ==="

# Step 1: Connect kubectl to the EKS cluster
echo "--- Step 1: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 2: Add the metrics-server Helm repo
echo "--- Step 2: Add Helm repo ---"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update metrics-server

# Step 3: Install metrics-server with Helm
# EKS kubelet certificates need --kubelet-insecure-tls for metrics-server to scrape nodes.
echo "--- Step 3: Install metrics-server ---"
helm upgrade -i "$RELEASE_NAME" metrics-server/metrics-server \
  --version "$CHART_VERSION" \
  -n "$NAMESPACE" \
  --set args="{--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}"

# Step 4: Wait until metrics-server is ready
echo "--- Step 4: Wait for metrics-server ---"
kubectl rollout status deployment/"$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s

# Step 5: Verify node and pod metrics (API may take a short moment after rollout)
echo "--- Step 5: Verify ---"
sleep 15
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=metrics-server
kubectl top nodes
kubectl top pods -n boutique-app

echo ""
echo "=== metrics-server install finished ==="
echo ""
echo "Next  (Scaling & Reliability):"
echo "  STEP 2 — verify CPU requests on boutique-app deployments"
echo "  STEP 3 — create HPA manifests for frontend and other services"
echo ""
