#!/bin/bash
set -e

# Run this script AFTER:
#   1. Tools are installed (install-tools.sh)
#   2. The EKS cluster is created (03_eks apply)
# AWS credentials come from the bastion IAM role — no aws configure needed.

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"

# Step 1: Add the EKS cluster to your kubeconfig file
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# Step 2: Check that kubectl can reach the cluster
kubectl get nodes
