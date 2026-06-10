#!/bin/bash
set -e

# This script runs automatically when the bastion host starts for the first time.
# All output is saved to /var/log/bastion-init.log

exec > /var/log/bastion-init.log 2>&1

echo "=== Bastion setup started ==="

# Create a folder for our scripts
mkdir -p /opt/bastion

# Copy install-tools.sh to the server
cat > /opt/bastion/install-tools.sh << 'INSTALL_EOF'
${install_tools}
INSTALL_EOF
chmod +x /opt/bastion/install-tools.sh

# Copy configure-kubeconfig.sh to the server (run this later, after EKS is ready)
cat > /opt/bastion/configure-kubeconfig.sh << 'CONFIGURE_EOF'
${configure_kube}
CONFIGURE_EOF
chmod +x /opt/bastion/configure-kubeconfig.sh

# Copy install-lbc.sh to the server (run manually after EKS is ready)
cat > /opt/bastion/install-lbc.sh << 'LBC_EOF'
${install_lbc}
LBC_EOF
chmod +x /opt/bastion/install-lbc.sh

# Copy install-gateway-api-crds.sh to the server (run manually after install-lbc.sh)
cat > /opt/bastion/install-gateway-api-crds.sh << 'GATEWAY_CRDS_EOF'
${install_gateway_crds}
GATEWAY_CRDS_EOF
chmod +x /opt/bastion/install-gateway-api-crds.sh

# Copy run-setup.sh — runs configure-kubeconfig, install-lbc, and install-gateway-api-crds in order
cat > /opt/bastion/run-setup.sh << 'RUN_SETUP_EOF'
${run_setup}
RUN_SETUP_EOF
chmod +x /opt/bastion/run-setup.sh

# Install the GitHub SSH key (same key every time you recreate the bastion)
mkdir -p /home/ubuntu/.ssh
cat > /home/ubuntu/.ssh/id_ed25519 << 'GITHUB_KEY_EOF'
${github_private_key}
GITHUB_KEY_EOF
echo "${github_public_key}" > /home/ubuntu/.ssh/id_ed25519.pub
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/id_ed25519
chmod 644 /home/ubuntu/.ssh/id_ed25519.pub
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Step 1: Install AWS CLI, kubectl, Helm, eksctl, and Git
echo "=== Step 1: Installing tools ==="
/opt/bastion/install-tools.sh

echo "=== Bastion setup finished ==="
echo "AWS credentials come from the instance IAM role (no aws configure needed)."
echo "GitHub SSH key is ready (same key after recreate — no need to re-add to GitHub)."
echo "Next steps:"
echo "  1. Create the EKS cluster (03_eks apply)"
echo "  2. Run: sudo -u ubuntu /opt/bastion/run-setup.sh"
echo "  3. Clone your repo: git clone git@github.com:YOUR-ORG/YOUR-REPO.git"
