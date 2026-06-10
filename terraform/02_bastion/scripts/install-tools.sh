#!/bin/bash
set -e

# This script installs tools on the bastion host.
# Run order: AWS CLI, kubectl, Helm, eksctl.

# Step 1: Update Ubuntu and install packages we need for the downloads below
apt-get update -y
apt-get install -y curl unzip ca-certificates gnupg apt-transport-https

# Step 2: Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# Step 3: Install kubectl
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubectl

# Step 4: Install Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Step 5: Install eksctl
curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" -o /tmp/eksctl.tar.gz
tar -xzf /tmp/eksctl.tar.gz -C /tmp
mv /tmp/eksctl /usr/local/bin/eksctl
rm -f /tmp/eksctl.tar.gz

# Step 6: Show installed versions
aws --version
kubectl version --client
helm version
eksctl version
