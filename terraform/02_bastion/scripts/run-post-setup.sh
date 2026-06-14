#!/bin/bash
set -e

# Run post-platform setup scripts in order (after run-setup.sh).
#
# Usage:
#   /opt/bastion/run-post-setup.sh
#
# Slack webhook: copied to ~/Webhook_URL.txt on bastion first boot.
# Source file: terraform/02_bastion/scripts/Webhook_URL.txt

# Load Slack webhook for step 3 (written by user_data on first boot from Webhook_URL.txt)
SLACK_WEBHOOK_URL=$(cat "$HOME/Webhook_URL.txt" 2>/dev/null | tr -d ' \r\n')
export SLACK_WEBHOOK_URL

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
