#!/bin/bash
set -e

# Install Elasticsearch via the ECK operator.
#
# Run AFTER install-eck-operator.sh (operator and ebs-aws StorageClass must exist).
# Waits for the PVC to bind and the Elasticsearch cluster health to turn green.
#
# Usage:
#   /opt/bastion/install-eck-elasticsearch.sh

NAMESPACE="logging"
RELEASE_NAME="eck-elasticsearch"
CHART_VERSION="0.18.0"
PVC_NAME="elasticsearch-data-eck-elasticsearch-es-default-0"

echo "=== ECK Elasticsearch install ==="

# Step 1: Connect kubectl to the EKS cluster
echo "--- Step 1: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 2: Add the Elastic Helm chart repo
echo "--- Step 2: Add Helm repo ---"
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo update elastic

# Step 3: Install Elasticsearch with Helm (ECK operator manages the cluster)
echo "--- Step 3: Install Elasticsearch ---"
helm upgrade -i "$RELEASE_NAME" elastic/eck-elasticsearch \
  --version "$CHART_VERSION" \
  -n "$NAMESPACE"

# Step 4: Wait until the Elasticsearch PVC is bound (EBS volume provisioned)
echo "--- Step 4: Wait for PVC bound ---"
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  "pvc/$PVC_NAME" \
  -n "$NAMESPACE" \
  --timeout=600s

# Step 5: Wait until Elasticsearch cluster health is green
echo "--- Step 5: Wait for Elasticsearch green ---"
kubectl wait elasticsearch/"$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=600s

# Step 6: Wait until the Elasticsearch pod is ready
echo "--- Step 6: Wait for Elasticsearch pod ---"
kubectl wait --for=condition=ready pod \
  -l "elasticsearch.k8s.elastic.co/cluster-name=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=600s

# Step 7: Verify Elasticsearch CR, PVC, and pods
echo "--- Step 7: Verify ---"
kubectl get elasticsearch -n "$NAMESPACE"
kubectl get pvc -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "=== ECK Elasticsearch install finished ==="
echo ""
echo "Next: install Filebeat log shipper"
echo "  /opt/bastion/install-eck-beats.sh"
echo ""
