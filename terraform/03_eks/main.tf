resource "aws_security_group" "add_sg_eks" {
  name   = "additional-eks-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description     = "HTTPS from bastion host"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.bastion.outputs.bastion_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "additional-eks-sg"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "terraform-cluster"
  kubernetes_version = "1.34"

  # Creates the OIDC provider for the cluster (needed for IRSA / install-lbc.sh)
  enable_irsa = true

  addons = {
    coredns = {}

    eks-pod-identity-agent = {
      before_compute = true
    }

    kube-proxy = {}

    vpc-cni = {
      before_compute = true
    }
  }

  endpoint_public_access                   = false
  enable_cluster_creator_admin_permissions = true

  # Let the bastion host run kubectl against this cluster (uses IAM role, not access keys)
  access_entries = {
    bastion_admin = {
      principal_arn = data.terraform_remote_state.bastion.outputs.bastion_iam_role_arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets

  additional_security_group_ids = [aws_security_group.add_sg_eks.id]

  eks_managed_node_groups = {
    example = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["c7i-flex.large"]
      min_size       = 2
      max_size       = 10
      desired_size   = 2

      # Tags required for Cluster Autoscaler to find and manage this node group
      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/terraform-cluster"   = "owned"
      }
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
