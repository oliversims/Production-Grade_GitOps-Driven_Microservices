#!/bin/bash
set -e

# Install Elastic Cloud on Kubernetes (ECK) operator and logging StorageClass.
#
# Run AFTER install-ebs-csi-driver.sh (EBS CSI driver must be ready for PVCs).
# Creates the logging namespace, installs the ECK operator, and applies ebs-aws StorageClass.
#
# Usage:
#   /opt/bastion/install-eck-operator.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
OBSERVABILITY_DIR="$REPO_DIR/observability"
STORAGECLASS_FILE="$OBSERVABILITY_DIR/storageclass.yaml"
NAMESPACE="logging"
OPERATOR_VERSION="3.3.0"

echo "=== ECK operator install ==="

# Step 1: Get observability files from GitHub
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

# Step 3: Create the logging namespace
echo "--- Step 3: Create namespace ---"
kubectl create namespace "$NAMESPACE" 2>/dev/null || echo "Namespace $NAMESPACE already exists."

# Step 4: Add the Elastic Helm chart repo
echo "--- Step 4: Add Helm repo ---"
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo update elastic

# Step 5: Install the ECK operator with Helm
echo "--- Step 5: Install ECK operator ---"
helm upgrade -i eck-operator elastic/eck-operator \
  --version "$OPERATOR_VERSION" \
  -n "$NAMESPACE" \
  --create-namespace

# Step 6: Wait until the ECK operator pod is ready
echo "--- Step 6: Wait for ECK operator ---"
kubectl rollout status statefulset/elastic-operator -n "$NAMESPACE" --timeout=300s

# Step 7: Apply the ebs-aws StorageClass for Elasticsearch PVCs
echo "--- Step 7: Apply StorageClass ---"
kubectl apply -f "$STORAGECLASS_FILE"

# Step 8: Verify operator pod and StorageClass
echo "--- Step 8: Verify ---"
kubectl get pods -n "$NAMESPACE"
kubectl get storageclass

echo ""
echo "=== ECK operator install finished ==="
echo ""
echo "Next: install Elasticsearch"
echo "  /opt/bastion/install-eck-elasticsearch.sh"
echo ""
