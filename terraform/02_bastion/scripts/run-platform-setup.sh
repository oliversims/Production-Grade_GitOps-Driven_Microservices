#!/bin/bash
set -e

# Run platform setup scripts in order (after 03_eks apply).
# Installs: Cluster Autoscaler, LBC, Gateway API, External DNS, Argo CD.
#
# Usage:
#   /opt/bastion/run-platform-setup.sh

echo ""
echo "========================================"
echo "  Platform setup started"
echo "========================================"
echo ""

echo "Step 1: Configure kubeconfig (connect kubectl to EKS)"
echo ""
sleep 2
/opt/bastion/configure-kubeconfig.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 2: Install Cluster Autoscaler"
echo ""
sleep 2
/opt/bastion/install-cluster-autoscaler.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 3: Install AWS Load Balancer Controller"
echo ""
sleep 2
/opt/bastion/install-lbc.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 4: Install Gateway API CRDs"
echo ""
sleep 2
/opt/bastion/install-gateway-api-crds.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 5: Clone and apply gateway-api-manifests"
echo ""
sleep 2
/opt/bastion/apply-gateway-manifests.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 6: Install External DNS"
echo ""
sleep 2
/opt/bastion/install-external-dns.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 7: Install ArgoCD"
echo ""
sleep 2
/opt/bastion/install-argocd.sh

echo ""
echo "========================================"
echo "  Platform setup finished"
echo "========================================"
echo ""
echo "Next step:"
echo "  /opt/bastion/run-app-monitoring-setup.sh"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
