#!/bin/bash
set -e

# Run scaling setup scripts in order (after run-logging-setup.sh).
# Installs: metrics-server, HPA manifests for boutique-app.
#
# Usage:
#   /opt/bastion/run-scaling-setup.sh

echo ""
echo "========================================"
echo "  Scaling setup started"
echo "========================================"
echo ""

echo "Step 1: Install metrics-server"
echo ""
sleep 2
/opt/bastion/install-metrics-server.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 2: Apply HPA manifests"
echo ""
sleep 2
/opt/bastion/apply-hpa.sh

echo ""
echo "----------------------------------------"
echo ""

echo "========================================"
echo "  Scaling setup finished (step 2 of 2)"
echo "========================================"
echo ""
echo "Verification snapshot:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
kubectl top nodes
kubectl get hpa -n boutique-app
kubectl get deploy frontend -n boutique-app
echo ""
echo "Check HPA status:"
echo "  kubectl get hpa -n boutique-app"
echo "  kubectl describe hpa frontend-hpa -n boutique-app"
echo ""
echo "Watch frontend scale under load:"
echo "  kubectl get pods -n boutique-app -l app=frontend -w"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
