#!/bin/bash
set -e

# Expose Kibana UI via the shared ALB Gateway.
# Run AFTER install-eck-kibana.sh (Kibana service must exist).
#
# Applies HTTPRoute + TargetGroupConfiguration manifests from observability/.
# External DNS creates kibana.oliver14.com records.
#
# Usage:
#   /opt/bastion/expose-kibana.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
OBSERVABILITY_DIR="$REPO_DIR/observability"

echo "=== Expose Kibana ==="

# Step 1: Get observability manifests from GitHub
echo "--- Step 1: Get observability manifests from GitHub ---"
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

# Step 3: Verify Kibana service exists
echo "--- Step 3: Verify Kibana service ---"
kubectl get svc eck-kibana-kb-http -n logging

# Step 4: Apply HTTPRoute and TargetGroupConfiguration
echo "--- Step 4: Apply Kibana route ---"
kubectl apply -f "$OBSERVABILITY_DIR/HTTProute-kibana.yaml"
kubectl apply -f "$OBSERVABILITY_DIR/target-grp-kibana.yaml"

# Step 5: Verify routes were created
echo "--- Step 5: Verify ---"
kubectl get httproute -n logging
kubectl get targetgroupconfiguration -n logging

echo ""
echo "=== Kibana exposed ==="
echo ""
echo "Kibana:  https://kibana.oliver14.com"
echo ""
echo "DNS may take a few minutes to propagate after first apply."
echo ""
echo "Login user: elastic"
echo "Password:"
kubectl get secret eck-elasticsearch-es-elastic-user -n logging -o go-template='{{.data.elastic | base64decode}}' && echo
echo ""
