#!/bin/bash
set -e

# Install Elasticsearch via the ECK operator.
#
# Run AFTER install-eck-operator.sh (operator and ebs-aws StorageClass must exist).
# Waits for the PVC to bind and the Elasticsearch cluster health to turn green.
#
# Safe to re-run: removes any previous Elasticsearch install and PVC first.
# This avoids Pending pods when nodes change AZ (EBS volume stuck in old zone).
#
# Usage:
#   /opt/bastion/install-eck-elasticsearch.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
VALUES_FILE="$REPO_DIR/observability/helm-values/eck-elasticsearch-0.18.0.yaml"
NAMESPACE="logging"
RELEASE_NAME="eck-elasticsearch"
CHART_VERSION="0.18.0"
PVC_NAME="elasticsearch-data-eck-elasticsearch-es-default-0"

echo "=== ECK Elasticsearch install ==="

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

# Step 4: Remove any previous Elasticsearch install (ensures re-run works after node/AZ changes)
echo "--- Step 4: Remove previous Elasticsearch install ---"
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "No previous Elasticsearch Helm release."
kubectl delete pvc "$PVC_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=120s
kubectl wait --for=delete pod \
  -l "elasticsearch.k8s.elastic.co/cluster-name=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=180s 2>/dev/null || echo "Elasticsearch pods already gone."

# Step 5: Install Elasticsearch with Helm (ECK operator manages the cluster)
echo "--- Step 5: Install Elasticsearch ---"
helm upgrade -i "$RELEASE_NAME" elastic/eck-elasticsearch \
  --version "$CHART_VERSION" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE"

# Step 6: Wait until the Elasticsearch PVC is bound (EBS volume provisioned)
echo "--- Step 6: Wait for PVC bound ---"
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  "pvc/$PVC_NAME" \
  -n "$NAMESPACE" \
  --timeout=600s

# Step 7: Wait until Elasticsearch cluster health is green
echo "--- Step 7: Wait for Elasticsearch green ---"
kubectl wait elasticsearch/"$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=600s

# Step 8: Wait until the Elasticsearch pod is ready
echo "--- Step 8: Wait for Elasticsearch pod ---"
kubectl wait --for=condition=ready pod \
  -l "elasticsearch.k8s.elastic.co/cluster-name=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=600s

# Step 9: Verify Elasticsearch CR, PVC, and pods
echo "--- Step 9: Verify ---"
kubectl get elasticsearch -n "$NAMESPACE"
kubectl get pvc -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "=== ECK Elasticsearch install finished ==="
echo ""
echo "Next: install Filebeat log shipper"
echo "  /opt/bastion/install-eck-beats.sh"
echo ""
