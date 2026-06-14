#!/bin/bash
set -e

# Run all cluster setup scripts in order (after 03_eks apply).
#
# Usage:
#   /opt/bastion/run-setup.sh

echo ""
echo "========================================"
echo "  Cluster setup started"
echo "========================================"
echo ""

echo "Step 1: Configure kubeconfig (connect kubectl to EKS)"
echo ""
sleep 2
/opt/bastion/configure-kubeconfig.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 2: Install AWS Load Balancer Controller"
echo ""
sleep 2
/opt/bastion/install-lbc.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 3: Install Gateway API CRDs"
echo ""
sleep 2
/opt/bastion/install-gateway-api-crds.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 4: Clone and apply gateway-api-manifests"
echo ""
sleep 2
/opt/bastion/apply-gateway-manifests.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 5: Install External DNS"
echo ""
sleep 2
/opt/bastion/install-external-dns.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 6: Install ArgoCD"
echo ""
sleep 2
/opt/bastion/install-argocd.sh

echo ""
echo "========================================"
echo "  Cluster setup finished"
echo "========================================"
echo ""
echo "Next steps (run manually):"
echo "  /opt/bastion/run-post-setup.sh"
echo ""
echo "  For Slack alerts:"
echo "  SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' /opt/bastion/run-post-setup.sh"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
