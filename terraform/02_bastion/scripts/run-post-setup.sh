#!/bin/bash
set -e

# Run post-platform setup scripts in order (after run-setup.sh).
#
# Usage:
#   /opt/bastion/run-post-setup.sh
#
# For Slack alerts, pass the webhook URL:
#   SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' /opt/bastion/run-post-setup.sh

echo ""
echo "========================================"
echo "  Post-setup started"
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
echo "========================================"
echo "  Post-setup finished"
echo "========================================"
echo ""
echo "Boutique app:  https://app.oliver14.com"
echo "Argo CD:       https://argocd.oliver14.com"
echo "Slack alerts:  #alertmanager"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
