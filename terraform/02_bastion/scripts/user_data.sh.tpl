#!/bin/bash
set -e

# Runs automatically on bastion first boot (via EC2 user_data).
# Keeps user_data small by cloning scripts from GitHub instead of embedding them.
# All output is saved to /var/log/bastion-init.log

# Redirect all output (both normal messages and errors) to a log file for debugging
exec > /var/log/bastion-init.log 2>&1

echo "=== Bastion setup started ==="

# Step 1: Install git (needed to clone scripts from GitHub)
apt-get update -y
apt-get install -y git openssh-client

# Step 2: Install GitHub SSH key for the ubuntu user
# Create the .ssh folder if it doesn't already exist
mkdir -p /home/ubuntu/.ssh

# Write the private key (injected by Terraform) into the id_ed25519 file
cat > /home/ubuntu/.ssh/id_ed25519 << 'GITHUB_KEY_EOF'
${github_private_key}
GITHUB_KEY_EOF

# Write the public key (injected by Terraform) into the id_ed25519.pub file
echo "${github_public_key}" > /home/ubuntu/.ssh/id_ed25519.pub

# Lock down the .ssh folder — only the owner can open it
chmod 700 /home/ubuntu/.ssh

# Lock down the private key — only the owner can read it (SSH will refuse to use it otherwise)
chmod 600 /home/ubuntu/.ssh/id_ed25519

# Make the public key readable by everyone (this is normal and expected)
chmod 644 /home/ubuntu/.ssh/id_ed25519.pub

# Give full ownership of the .ssh folder and everything inside it to the ubuntu user
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Fetch GitHub's fingerprint and save it as a trusted host so SSH never prompts "are you sure?"
sudo -u ubuntu ssh-keyscan github.com >> /home/ubuntu/.ssh/known_hosts 2>/dev/null

# Give ownership of known_hosts to the ubuntu user
chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts

# Lock down known_hosts — only the owner can read it
chmod 600 /home/ubuntu/.ssh/known_hosts

# Set the Git username for the ubuntu user
sudo -u ubuntu git config --global user.name "oliversims"

# Set the Git email for the ubuntu user
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
