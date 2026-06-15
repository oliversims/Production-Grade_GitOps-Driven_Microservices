#!/bin/bash
set -e

# Bastion first-boot setup (runs automatically via EC2 user_data).
#
# Triggered by: terraform apply (or bastion replace) in terraform/02_bastion
# Slack webhook: injected from terraform/02_bastion/scripts/Webhook_URL.txt (gitignored on laptop)
#
# All output is saved to /var/log/bastion-init.log

exec > /var/log/bastion-init.log 2>&1

GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

echo "=== Bastion setup started ==="

# Step 1: Install git (needed to clone scripts from GitHub)
echo "--- Step 1: Install git ---"
apt-get update -y
apt-get install -y git

# Step 2: Git identity for the ubuntu user (sparse clone runs as ubuntu)
echo "--- Step 2: Configure git ---"
sudo -u ubuntu git config --global user.name "oliversims"
sudo -u ubuntu git config --global user.email "simsoliver1994@gmail.com"

# Step 3: Clone bastion scripts from GitHub into /tmp/bastion-repo
echo "--- Step 3: Clone scripts from GitHub ---"
mkdir -p /opt/bastion
sudo -u ubuntu git clone --filter=blob:none --sparse -b main \
  "$GITHUB_REPO_URL" /tmp/bastion-repo
cd /tmp/bastion-repo
sudo -u ubuntu git sparse-checkout set terraform/02_bastion/scripts

# Step 4: Copy .sh files to /opt/bastion (where you run them from)
echo "--- Step 4: Copy scripts to /opt/bastion ---"
cp terraform/02_bastion/scripts/*.sh /opt/bastion/
cp terraform/02_bastion/scripts/aws-load-balancer-controller-iam-policy.json /opt/bastion/
chmod +x /opt/bastion/*.sh

# Step 5: Write Slack webhook for run-app-monitoring-setup.sh (step 3)
# Terraform reads Webhook_URL.txt on your laptop and injects ${slack_webhook_url} here.
# run-app-monitoring-setup.sh reads /home/ubuntu/Webhook_URL.txt and exports SLACK_WEBHOOK_URL.
echo "--- Step 5: Write Slack webhook file ---"
cat > /home/ubuntu/Webhook_URL.txt <<'WEBHOOK_EOF'
${slack_webhook_url}
WEBHOOK_EOF
chmod 600 /home/ubuntu/Webhook_URL.txt
chown ubuntu:ubuntu /home/ubuntu/Webhook_URL.txt

# Step 6: Install kubectl, helm, eksctl, aws cli
echo "--- Step 6: Install tools ---"
/opt/bastion/install-tools.sh

echo "=== Bastion setup finished ==="
echo "Next steps:"
echo "  1. Create the EKS cluster (03_eks apply)"
echo "  2. Run: /opt/bastion/run-platform-setup.sh"
echo "  3. Run: /opt/bastion/run-app-monitoring-setup.sh"
echo "  4. Run: /opt/bastion/run-logging-setup.sh"
