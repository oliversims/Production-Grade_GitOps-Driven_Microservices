#!/bin/bash
set -e

# Install Kibana via the ECK operator.
#
# Run AFTER install-eck-elasticsearch.sh (Elasticsearch must be green).
# Connects to the eck-elasticsearch cluster in the logging namespace.
#
# Usage:
#   /opt/bastion/install-eck-kibana.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
VALUES_FILE="$REPO_DIR/observability/helm-values/eck-kibana-0.18.0.yaml"
NAMESPACE="logging"
RELEASE_NAME="eck-kibana"
CHART_VERSION="0.18.0"

echo "=== ECK Kibana install ==="

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

# Step 4: Install Kibana with Helm (ECK operator manages the deployment)
echo "--- Step 4: Install Kibana ---"
helm upgrade -i "$RELEASE_NAME" elastic/eck-kibana \
  --version "$CHART_VERSION" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE"

# Step 5: Wait until the Kibana CR health is green
echo "--- Step 5: Wait for Kibana green ---"
kubectl wait kibana/"$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=600s

# Step 6: Wait until the Kibana pod is ready
echo "--- Step 6: Wait for Kibana pod ---"
kubectl wait --for=condition=ready pod \
  -l "kibana.k8s.elastic.co/name=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=600s

# Step 7: Verify Kibana CR and pods
echo "--- Step 7: Verify ---"
kubectl get kibana -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l "kibana.k8s.elastic.co/name=$RELEASE_NAME"

echo ""
echo "=== ECK Kibana install finished ==="
echo ""
echo "Next: expose Kibana via the shared ALB Gateway"
echo "  /opt/bastion/expose-kibana.sh"
echo ""
