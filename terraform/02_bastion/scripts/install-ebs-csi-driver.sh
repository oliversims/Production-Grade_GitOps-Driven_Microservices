#!/bin/bash
set -e

# Install the AWS EBS CSI driver EKS addon.
#
# Required before Elasticsearch (ECK) — it dynamically provisions EBS volumes for PVCs.
# Run AFTER run-platform-setup.sh (EKS cluster must exist).
#
# Safe to re-run: --override-existing-serviceaccounts and --force update an existing install.
#
# Usage:
#   /opt/bastion/install-ebs-csi-driver.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
ADDON_NAME="aws-ebs-csi-driver"
SA_NAMESPACE="kube-system"
SA_NAME="ebs-csi-controller-sa"
EBS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

echo "=== AWS EBS CSI driver install ==="

# Step 1: Connect kubectl to the EKS cluster
echo "--- Step 1: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 2: Show current addon status (informational only — install continues either way)
echo "--- Step 2: Show current addon status ---"
aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name "$ADDON_NAME" \
  --region "$REGION" \
  --query 'addon.status' \
  --output text 2>/dev/null \
  || echo "Addon not installed yet — will install in step 5."

# Step 3: Create the controller service account with an IAM role (IRSA)
echo "--- Step 3: Create service account with IAM role ---"
eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace="$SA_NAMESPACE" \
  --name="$SA_NAME" \
  --attach-policy-arn="$EBS_CSI_POLICY_ARN" \
  --override-existing-serviceaccounts \
  --region "$REGION" \
  --approve

# Step 4: Read the IAM role ARN from the service account annotation
echo "--- Step 4: Get IAM role ARN ---"
ROLE_ARN=$(kubectl get sa "$SA_NAME" -n "$SA_NAMESPACE" \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
echo "Role ARN: $ROLE_ARN"

# Step 5: Install (or update) the EBS CSI driver as an EKS managed addon
echo "--- Step 5: Install EKS addon ---"
eksctl create addon \
  --cluster="$CLUSTER_NAME" \
  --name="$ADDON_NAME" \
  --version latest \
  --service-account-role-arn="$ROLE_ARN" \
  --region "$REGION" \
  --force \
  --wait

# Step 6: Wait until EBS CSI pods are ready (addon creates them after status ACTIVE)
echo "--- Step 6: Wait for EBS CSI pods ---"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -n "$SA_NAMESPACE" \
  --timeout=300s

# Step 7: Verify controller and node pods are running
echo "--- Step 7: Verify ---"
kubectl get pods -n "$SA_NAMESPACE" -l app.kubernetes.io/name=aws-ebs-csi-driver

echo ""
echo "=== AWS EBS CSI driver install finished ==="
echo ""
echo "Next: install the ECK logging stack"
echo "  /opt/bastion/install-eck-logging.sh"
echo ""
