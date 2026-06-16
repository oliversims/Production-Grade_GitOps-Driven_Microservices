#!/bin/bash
set -e

# Expose Grafana and Prometheus UIs via the shared ALB Gateway.
# Run AFTER install-kube-prometheus-stack.sh (monitoring services must exist).
#
# Applies HTTPRoute + TargetGroupConfiguration manifests from observability/.
# External DNS creates grafana.oliver14.com and prometheus.oliver14.com records.
#
# Usage:
#   /opt/bastion/expose-grafana-prometheus.sh

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
OBSERVABILITY_DIR="$REPO_DIR/observability"

echo "=== Expose Grafana and Prometheus ==="

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

# Step 3: Verify kube-prometheus-stack services exist
echo "--- Step 3: Verify monitoring services ---"
kubectl get svc kube-prometheus-stack-grafana kube-prometheus-stack-prometheus -n monitoring

# Step 4: Apply HTTPRoutes and TargetGroupConfigurations
echo "--- Step 4: Apply Grafana and Prometheus routes ---"
kubectl apply -f "$OBSERVABILITY_DIR/HTTProute-grafana.yaml"
kubectl apply -f "$OBSERVABILITY_DIR/target-grp-grafana.yaml"
kubectl apply -f "$OBSERVABILITY_DIR/HTTProute-prometheus.yaml"
kubectl apply -f "$OBSERVABILITY_DIR/target-grp-prometheus.yaml"

# Step 5: Verify routes were created
echo "--- Step 5: Verify ---"
kubectl get httproute -n monitoring
kubectl get targetgroupconfiguration -n monitoring

echo ""
echo "=== Grafana and Prometheus exposed ==="
echo ""
echo "Grafana:     https://grafana.oliver14.com"
echo "Prometheus:  https://prometheus.oliver14.com"
echo ""
echo "DNS may take a few minutes to propagate after first apply."
echo ""
echo "Grafana admin password:"
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d && echo
echo ""
