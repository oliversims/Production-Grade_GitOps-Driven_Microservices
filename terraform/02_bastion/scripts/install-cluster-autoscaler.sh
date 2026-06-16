#!/bin/bash
set -e

# Install Cluster Autoscaler (adds/removes EKS nodes automatically).
#
# Run AFTER configure-kubeconfig.sh and AFTER 03_eks apply (with CA tags on the node group).
# When pods cannot schedule (e.g. Insufficient memory), CA increases the node group up to max_size.
# When nodes are underused, CA removes them down to min_size.
#
# Usage:
#   /opt/bastion/install-cluster-autoscaler.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
POLICY_NAME="AmazonEKSClusterAutoscalerPolicy"
SA_NAMESPACE="kube-system"
SA_NAME="cluster-autoscaler"
DEPLOYMENT_NAME="cluster-autoscaler-aws-cluster-autoscaler"

echo "=== Cluster Autoscaler install ==="

# Step 1: Connect kubectl to the EKS cluster
echo "--- Step 1: Configure kubeconfig ---"
/opt/bastion/configure-kubeconfig.sh

# Step 2: Create IAM policy for Cluster Autoscaler (skip if it already exists)
echo "--- Step 2: Create IAM policy ---"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

cat > /tmp/cluster-autoscaler-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": ["*"]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document file:///tmp/cluster-autoscaler-policy.json \
  2>/dev/null || echo "IAM policy already exists, using $POLICY_ARN"

# Step 3: Create the service account with an IAM role (IRSA)
echo "--- Step 3: Create service account with IAM role ---"
eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace="$SA_NAMESPACE" \
  --name="$SA_NAME" \
  --attach-policy-arn="$POLICY_ARN" \
  --override-existing-serviceaccounts \
  --region "$REGION" \
  --approve

# Step 4: Add the Cluster Autoscaler Helm repo
echo "--- Step 4: Add Helm repo ---"
helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo update autoscaler

# Step 5: Install Cluster Autoscaler with Helm
# autoDiscovery finds the node group via Terraform tags on the ASG
echo "--- Step 5: Install Cluster Autoscaler ---"
helm upgrade -i cluster-autoscaler autoscaler/cluster-autoscaler \
  -n "$SA_NAMESPACE" \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" \
  --set awsRegion="$REGION" \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name="$SA_NAME" \
  --version 9.53.0

# Step 6: Wait until the Cluster Autoscaler pod is ready
echo "--- Step 6: Wait for Cluster Autoscaler ---"
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$SA_NAMESPACE" --timeout=300s

# Step 7: Verify the pod is running
echo "--- Step 7: Verify ---"
kubectl get pods -n "$SA_NAMESPACE" -l app.kubernetes.io/name=aws-cluster-autoscaler

echo ""
echo "=== Cluster Autoscaler install finished ==="
echo ""
echo "Node group: min 2, max 10 (set in terraform/03_eks)"
echo "CA will add nodes when pods are Pending, remove nodes when underused."
echo ""
