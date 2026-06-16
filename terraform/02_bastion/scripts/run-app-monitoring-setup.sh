#!/bin/bash
set -e

# Run app and monitoring setup scripts in order (after run-platform-setup.sh).
# Installs: Image Updater, boutique app, kube-prometheus-stack, Grafana/Prometheus routes.
#
# Usage:
#   /opt/bastion/run-app-monitoring-setup.sh
#
# Slack webhook: copied to ~/Webhook_URL.txt on bastion first boot.
# Source file: terraform/02_bastion/scripts/Webhook_URL.txt

# Load Slack webhook for step 3 (written by user_data on first boot from Webhook_URL.txt)
SLACK_WEBHOOK_URL=$(cat "$HOME/Webhook_URL.txt" 2>/dev/null | tr -d ' \r\n')
export SLACK_WEBHOOK_URL

echo ""
echo "========================================"
echo "  App and monitoring setup started"
echo "========================================"
echo ""

echo "Step 1: Install Argo CD Image Updater"
echo ""
sleep 2
/opt/bastion/install-argocd-image-updater.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 2: Deploy boutique app via Argo CD"
echo ""
sleep 2
/opt/bastion/apply-boutique-app.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 3: Install kube-prometheus-stack"
echo ""
sleep 2
/opt/bastion/install-kube-prometheus-stack.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 4: Expose Grafana and Prometheus"
echo ""
sleep 2
/opt/bastion/expose-grafana-prometheus.sh

echo ""
echo "========================================"
echo "  App and monitoring setup finished"
echo "========================================"
echo ""
echo "Verification snapshot:"
kubectl get application -n argocd boutique-app
kubectl get pods -n boutique-app
kubectl get pods -n monitoring
kubectl get httproute -n monitoring
kubectl get targetgroupconfiguration -n monitoring
echo ""
echo "Boutique app:  https://app.oliver14.com"
echo "Grafana:       https://grafana.oliver14.com"
echo "Prometheus:    https://prometheus.oliver14.com"
echo "Slack alerts:  #alertmanager"
echo ""
echo "Next step:"
echo "  /opt/bastion/run-logging-setup.sh"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
