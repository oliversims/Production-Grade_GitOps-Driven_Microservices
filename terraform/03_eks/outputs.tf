output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "vpc_id" {
  description = "VPC ID used by the EKS cluster"
  value       = data.terraform_remote_state.vpc.outputs.vpc_id
}
