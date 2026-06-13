#!/bin/bash
set -e

# Runs automatically on bastion first boot (via EC2 user_data).
# Clones scripts from the public GitHub repo (HTTPS — no SSH key required).
# All output is saved to /var/log/bastion-init.log

exec > /var/log/bastion-init.log 2>&1

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

echo "=== Bastion setup started ==="

apt-get update -y
apt-get install -y git

sudo -u ubuntu git config --global user.name "oliversims"
sudo -u ubuntu git config --global user.email "simsoliver1994@gmail.com"

mkdir -p /opt/bastion
sudo -u ubuntu git clone --filter=blob:none --sparse -b main \
  "$GITHUB_REPO_URL" /tmp/bastion-repo
cd /tmp/bastion-repo
sudo -u ubuntu git sparse-checkout set terraform/02_bastion/scripts
cp terraform/02_bastion/scripts/*.sh /opt/bastion/
chmod +x /opt/bastion/*.sh

echo "=== Installing tools ==="
/opt/bastion/install-tools.sh

echo "=== Bastion setup finished ==="
echo "Next steps:"
echo "  1. Create the EKS cluster (03_eks apply)"
echo "  2. Run: /opt/bastion/run-setup.sh"
echo "  3. Run: /opt/bastion/install-argocd-image-updater.sh"
echo "  4. Run: /opt/bastion/apply-boutique-app.sh"
