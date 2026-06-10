#!/bin/bash
set -e

# Install Gateway API CRDs.
#
# Run this AFTER install-lbc.sh.
# Run as the ubuntu user (not sudo) — kubectl needs /home/ubuntu/.kube/config.
#
# Usage:
#   /opt/bastion/install-gateway-api-crds.sh

echo "=== Gateway API CRDs install ==="

# Step 1: Make sure kubectl can reach the cluster
echo "--- Step 1: Check cluster access ---"
kubectl get nodes

# Step 2: Install standard Gateway API CRDs (required for Gateway and HTTPRoute)
echo "--- Step 2: Install standard Gateway API CRDs ---"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml

# Step 3: Install AWS LBC Gateway API CRDs (required for LoadBalancerConfiguration)
echo "--- Step 3: Install AWS LBC Gateway API CRDs ---"
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml

# Step 4: Show installed CRDs
echo "--- Step 4: Show result ---"
kubectl get crd | grep gateway

echo "=== Done ==="
