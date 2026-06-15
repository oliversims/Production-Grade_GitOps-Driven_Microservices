#!/bin/bash
set -e

# Run logging stack setup scripts in order (after run-app-monitoring-setup.sh).
#
# Usage:
#   /opt/bastion/run-logging-setup.sh

echo ""
echo "========================================"
echo "  Logging setup started"
echo "========================================"
echo ""

echo "Step 1: Install AWS EBS CSI driver"
echo ""
sleep 2
/opt/bastion/install-ebs-csi-driver.sh

echo ""
echo "----------------------------------------"
echo ""

echo "========================================"
echo "  Logging setup finished (step 1 of 3)"
echo "========================================"
echo ""
echo "Next steps (when scripts are added):"
echo "  /opt/bastion/install-eck-logging.sh"
echo "  /opt/bastion/expose-kibana.sh"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
