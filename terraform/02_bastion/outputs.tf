output "bastion_sg_id" {
  description = "Security group ID for the bastion host"
  value       = aws_security_group.bastion_sg.id
}

output "bastion_iam_role_arn" {
  description = "IAM role ARN for the bastion (used by EKS to allow kubectl access)"
  value       = aws_iam_role.bastion.arn
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.bastion_host.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion host"
  value       = "ssh -i ${abspath(path.module)}/bastion-key.pem ubuntu@${module.bastion_host.public_ip}"
}

output "configure_kubeconfig_command" {
  description = "Run on the bastion after 03_eks apply"
  value       = "/opt/bastion/configure-kubeconfig.sh"
}

output "install_lbc_command" {
  description = "Run on the bastion after configure-kubeconfig.sh"
  value       = "/opt/bastion/install-lbc.sh"
}

output "install_gateway_api_crds_command" {
  description = "Run on the bastion after install-lbc.sh"
  value       = "/opt/bastion/install-gateway-api-crds.sh"
}

output "install_argocd_command" {
  description = "Run on the bastion after install-external-dns.sh (or use run-setup.sh for all steps)"
  value       = "/opt/bastion/install-argocd.sh"
}

# output "github_ssh_public_key" {
#   description = "Add this to GitHub once (Settings → SSH keys). Same key is reused when the bastion is recreated."
#   value       = tls_private_key.github_key.public_key_openssh
# }

# output "github_ssh_public_key_file" {
#   description = "Path to the GitHub public key file on your machine"
#   value       = abspath("${path.module}/github-key.pub")
# }
