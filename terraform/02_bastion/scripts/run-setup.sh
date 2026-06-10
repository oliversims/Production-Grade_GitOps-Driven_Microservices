#!/bin/bash
set -e

# Run all cluster setup scripts in order (after 03_eks apply).
#
# Usage:
#   /opt/bastion/run-setup.sh

echo "=== Cluster setup started ==="

echo "Step 1: Configure kubeconfig (connect kubectl to EKS)"
sleep 2
/opt/bastion/configure-kubeconfig.sh

echo "Step 2: Install AWS Load Balancer Controller"
sleep 2
/opt/bastion/install-lbc.sh

echo "Step 3: Install Gateway API CRDs"
sleep 2
/opt/bastion/install-gateway-api-crds.sh

echo "=== Cluster setup finished ==="
