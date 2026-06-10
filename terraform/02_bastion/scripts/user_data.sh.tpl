#!/bin/bash
set -e

# Runs automatically on bastion first boot (via EC2 user_data).
# Keeps user_data small by cloning scripts from GitHub instead of embedding them.
# All output is saved to /var/log/bastion-init.log

exec > /var/log/bastion-init.log 2>&1

echo "=== Bastion setup started ==="

# Step 1: Install git (needed to clone scripts from GitHub)
apt-get update -y
apt-get install -y git openssh-client

# Step 2: Install GitHub SSH key for the ubuntu user
mkdir -p /home/ubuntu/.ssh
cat > /home/ubuntu/.ssh/id_ed25519 << 'GITHUB_KEY_EOF'
${github_private_key}
GITHUB_KEY_EOF
echo "${github_public_key}" > /home/ubuntu/.ssh/id_ed25519.pub
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/id_ed25519
chmod 644 /home/ubuntu/.ssh/id_ed25519.pub
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
sudo -u ubuntu ssh-keyscan github.com >> /home/ubuntu/.ssh/known_hosts 2>/dev/null
chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts
chmod 600 /home/ubuntu/.ssh/known_hosts
sudo -u ubuntu git config --global user.name "oliversims"
sudo -u ubuntu git config --global user.email "simsoliver1994@gmail.com"

# Step 3: Clone scripts from GitHub and copy to /opt/bastion
mkdir -p /opt/bastion
sudo -u ubuntu git clone --filter=blob:none --sparse -b main \
  git@github.com:oliversims/Production-Grade_GitOps-Driven_Microservices.git /tmp/bastion-repo
cd /tmp/bastion-repo
sudo -u ubuntu git sparse-checkout set terraform/02_bastion/scripts
cp terraform/02_bastion/scripts/*.sh /opt/bastion/
chmod +x /opt/bastion/*.sh

# Step 4: Install AWS CLI, kubectl, Helm, and eksctl
echo "=== Installing tools ==="
/opt/bastion/install-tools.sh

echo "=== Bastion setup finished ==="
echo "Next steps:"
echo "  1. Create the EKS cluster (03_eks apply)"
echo "  2. Run: /opt/bastion/run-setup.sh"
