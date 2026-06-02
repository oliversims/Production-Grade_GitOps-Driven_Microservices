# -------------------------------------------------------
# SECURITY GROUP: Additional Security Group for EKS Cluster
# -------------------------------------------------------
# This security group is attached to the EKS cluster to allow
# the bastion host to communicate with the Kubernetes API server.
# Without this, you wouldn't be able to run kubectl commands
# from the bastion host to manage the cluster.
resource "aws_security_group" "add_sg_eks" {
  name   = "additional-eks-sg"
  vpc_id = module.vpc.vpc_id # Attach to the same VPC as the cluster

  # INBOUND: Allow HTTPS (port 443) traffic ONLY from the bastion host's security group.
  # Port 443 is used by the Kubernetes API server.
  # By referencing the security group instead of an IP, any instance
  # in the bastion_sg is automatically allowed — no hardcoded IPs needed.
  ingress {
    description     = "HTTPS from bastion host"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id] # Only the bastion host can reach the API
  }

  # OUTBOUND: Allow all outbound traffic.
  # Needed so the cluster can communicate back to nodes, AWS services, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 means ALL protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic to anywhere
  }

  tags = {
    Name = "additional-eks-sg"
  }
}

# -------------------------------------------------------
# MODULE: EKS — Create a managed Kubernetes cluster on AWS
# -------------------------------------------------------
# Uses the official Terraform EKS module to provision a fully
# managed Kubernetes cluster, including the control plane,
# node groups, IAM roles, and add-ons.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0" # Use any patch version of v21 — avoids breaking changes from major upgrades

  name               = "terraform-cluster" # Name of the EKS cluster
  kubernetes_version = "1.34"              # Kubernetes version to deploy

  # -------------------------------------------------------
  # EKS ADD-ONS: Managed plugins that extend Kubernetes
  # -------------------------------------------------------
  addons = {
    # CoreDNS: Handles DNS resolution inside the cluster (e.g., service discovery)
    coredns = {}

    # EKS Pod Identity Agent: Allows pods to assume IAM roles directly
    # before_compute = true means it's installed BEFORE worker nodes join
    eks-pod-identity-agent = {
      before_compute = true
    }

    # kube-proxy: Maintains network rules on each node for pod-to-pod communication
    kube-proxy = {}

    # VPC CNI: Assigns real VPC IP addresses to pods so they can communicate
    # natively within the VPC. Installed before nodes join the cluster.
    vpc-cni = {
      before_compute = true
    }
  }

  # Disable public access to the Kubernetes API server.
  # The API endpoint is only reachable from within the VPC —
  # this is why the bastion host is needed to run kubectl commands.
  endpoint_public_access = false

  # Automatically grants the Terraform caller (your IAM user/role)
  # full admin permissions on the cluster via a cluster access entry.
  # Useful so you don't get locked out after the cluster is created.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id          # Deploy the cluster into our VPC
  subnet_ids = module.vpc.private_subnets # Place worker nodes in private subnets (no direct internet exposure)

  # Attach the additional security group created above to allow
  # bastion → Kubernetes API server communication on port 443.
  additional_security_group_ids = [aws_security_group.add_sg_eks.id]

  # -------------------------------------------------------
  # MANAGED NODE GROUPS: The worker nodes that run your pods
  # -------------------------------------------------------
  eks_managed_node_groups = {
    example = {
      # AL2023 is Amazon's latest EKS-optimized AMI (default from Kubernetes 1.30+)
      ami_type = "AL2023_x86_64_STANDARD"

      # c7i-flex.large: A cost-flexible compute-optimized instance type.
      # "flex" variants automatically adjust between baseline and burst performance.
      instance_types = ["c7i-flex.large"]

      min_size     = 2  # Always keep at least 2 nodes running for high availability
      max_size     = 10 # Allow scaling up to 10 nodes under heavy load
      desired_size = 2  # Start with 2 nodes
    }
  }

  tags = {
    Environment = "dev"  # Development environment
    Terraform   = "true" # Marks all resources as Terraform-managed
  }
}