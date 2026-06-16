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

echo "Step 5: Install Kibana"
echo ""
sleep 2
/opt/bastion/install-eck-kibana.sh

echo ""
echo "----------------------------------------"
echo ""

echo "Step 6: Expose Kibana"
echo ""
sleep 2
/opt/bastion/expose-kibana.sh

echo ""
echo "----------------------------------------"
echo ""

echo "========================================"
echo "  Logging setup finished (step 6 of 6)"
echo "========================================"
echo ""
echo "Verification snapshot:"
kubectl get ns logging
kubectl get elasticsearch -n logging
kubectl get beats -n logging
kubectl get kibana -n logging
kubectl get httproute -n logging
kubectl get targetgroupconfiguration -n logging
kubectl get pvc -n logging
kubectl get pods -n logging
echo ""
echo "Kibana:  https://kibana.oliver14.com"
echo ""
echo "Next step:"
echo "  /opt/bastion/run-scaling-setup.sh"
echo ""
echo "Before terraform destroy, run:"
echo "  /opt/bastion/delete-kubernetes-workloads.sh"
echo ""
