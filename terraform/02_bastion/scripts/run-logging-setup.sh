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

echo "Step 2: Install ECK operator"
echo ""
sleep 2
/opt/bastion/install-eck-operator.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 3: Install Elasticsearch"
echo ""
sleep 2
/opt/bastion/install-eck-elasticsearch.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 4: Install Filebeat"
echo ""
sleep 2
/opt/bastion/install-eck-beats.sh

echo ""
echo "----------------------------------------"
echo ""

echo "========================================"
echo "  Logging setup finished (step 4 of 5)"
echo "========================================"
echo ""
echo "Next steps (when scripts are added):"
echo "  /opt/bastion/install-eck-kibana.sh"
echo "  /opt/bastion/expose-kibana.sh"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
