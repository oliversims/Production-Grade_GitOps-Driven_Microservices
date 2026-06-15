#!/bin/bash
set -e

# Install Filebeat via the ECK operator (DaemonSet log shipper).
#
# Run AFTER install-eck-elasticsearch.sh (Elasticsearch must be green).
# Ships container logs from every node to Elasticsearch.
#
# Usage:
#   /opt/bastion/install-eck-beats.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
VALUES_FILE="$REPO_DIR/observability/helm-values/eck-beats-0.18.0.yaml"
NAMESPACE="logging"
RELEASE_NAME="eck-beats"
CHART_VERSION="0.18.0"

echo "=== ECK Filebeat install ==="

# Step 1: Get observability Helm values from GitHub
echo "--- Step 1: Get observability files from GitHub ---"
cd "$HOME"

# Clone if missing; ignore error if repo already exists
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"

# Add observability folder if sparse checkout already exists; otherwise init it
git sparse-checkout add observability 2>/dev/null || git sparse-checkout set observability
git pull

# Step 2: Connect kubectl to the EKS cluster
echo "--- Step 2: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 3: Add the Elastic Helm chart repo
echo "--- Step 3: Add Helm repo ---"
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo update elastic

# Step 4: Install Filebeat with Helm (ECK operator creates a DaemonSet per node)
echo "--- Step 4: Install Filebeat ---"
helm upgrade -i "$RELEASE_NAME" elastic/eck-beats \
  --version "$CHART_VERSION" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE"

# Step 5: Wait until the Beat CR health is green
echo "--- Step 5: Wait for Filebeat green ---"
kubectl wait beats/"$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=600s

# Step 6: Wait until all Filebeat DaemonSet pods are ready
echo "--- Step 6: Wait for Filebeat pods ---"
kubectl wait --for=condition=ready pod \
  -l "beat.k8s.elastic.co/name=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=600s

# Step 7: Verify Beat CR and pods
echo "--- Step 7: Verify ---"
kubectl get beats -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "=== ECK Filebeat install finished ==="
echo ""
echo "Next: install Kibana"
echo "  /opt/bastion/install-eck-kibana.sh"
echo ""
