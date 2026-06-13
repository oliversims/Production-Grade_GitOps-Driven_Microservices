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
