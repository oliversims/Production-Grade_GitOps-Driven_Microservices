output "cluster_name" {
  value = module.eks.cluster_name
}
output "bastion_ssh_command" {
  value = "ssh -i ${abspath(path.module)}/bastion-key.pem ubuntu@${module.bastion_host.public_ip}"
}
output "vpc_id" {
  value = module.vpc.vpc_id
}