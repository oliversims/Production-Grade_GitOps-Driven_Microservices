#!/bin/bash
set -e

# Install kube-prometheus-stack (Prometheus, Grafana, Alertmanager).
#
# Run AFTER run-platform-setup.sh (cluster + platform must be ready).
# Also creates the Slack webhook secret for Alertmanager notifications.
#
# Prerequisite: create Incoming Webhook in Slack for #alertmanager channel.
# https://api.slack.com/apps
#
# Usage:
#   SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' /opt/bastion/install-kube-prometheus-stack.sh
#
# Or edit SLACK_WEBHOOK_URL below before running.

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"
REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
VALUES_FILE="$REPO_DIR/observability/helm-values/kube-prom-stack-81.6.3.yaml"

# Paste your Slack Incoming Webhook URL here, or pass SLACK_WEBHOOK_URL when running the script.
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-PASTE_YOUR_WEBHOOK_URL_HERE}"

echo "=== kube-prometheus-stack install ==="

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

# Step 3: Create the monitoring namespace
echo "--- Step 3: Create namespace ---"
kubectl create namespace monitoring 2>/dev/null || echo "Namespace monitoring already exists."

# Step 4: Create the Slack webhook secret for Alertmanager
# Mounted at /etc/alertmanager/secrets/alertmanager-slack-webhook/slack-webhook-url
echo "--- Step 4: Create Slack webhook secret ---"
kubectl delete secret alertmanager-slack-webhook -n monitoring 2>/dev/null || true
kubectl create secret generic alertmanager-slack-webhook \
  --from-literal=slack-webhook-url="$SLACK_WEBHOOK_URL" \
  -n monitoring

# Step 5: Add the kube-prometheus-stack Helm repo
echo "--- Step 5: Add Helm repo ---"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

# Step 6: Install kube-prometheus-stack with Helm
echo "--- Step 6: Install kube-prometheus-stack ---"
helm upgrade -i kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f "$VALUES_FILE" \
  -n monitoring \
  --version 81.6.3 \
  --create-namespace

# Step 7: Verify pods and services are running
echo "--- Step 7: Verify ---"
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=600s
kubectl get pods -n monitoring
kubectl get svc -n monitoring

echo ""
echo "=== kube-prometheus-stack install finished ==="
echo ""
echo "Slack: critical alerts go to #alertmanager"
echo ""
echo "Next: expose Grafana and Prometheus UIs"
echo "  /opt/bastion/expose-grafana-prometheus.sh"
echo ""
echo "Grafana admin password:"
echo "  kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath=\"{.data.admin-password}\" | base64 -d && echo"
echo ""
