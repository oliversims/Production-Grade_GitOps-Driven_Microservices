# -------------------------------------------------------
# MODULE: VPC — Create a full VPC using the official
#         Terraform AWS VPC community module
# -------------------------------------------------------
# Instead of manually defining aws_vpc, aws_subnet,
# aws_route_table, etc., this module handles all of that
# for you under the hood with a clean, simple interface.
# Source: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "test-vpc-01" # Name tag applied to the VPC and its resources
  cidr = "10.0.0.0/16" # The overall IP range for the entire VPC (/16 = 65,536 addresses)

  # The three Availability Zones to spread subnets across.
  # Using multiple AZs ensures high availability and fault tolerance.
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # One private subnet per AZ — these have NO direct internet access.
  # Used for backend resources like databases, app servers, etc.
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  # One public subnet per AZ — these have direct internet access via an Internet Gateway.
  # Used for load balancers, bastion hosts, NAT Gateways, etc.
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Creates a NAT Gateway so that private subnet resources can
  # initiate outbound internet traffic (e.g., to download packages)
  # without being directly reachable from the internet.
  enable_nat_gateway = true

  # No VPN Gateway needed for this setup.
  # A VPN Gateway would be used to connect your VPC to an on-premises network.
  enable_vpn_gateway = false

  # Use only ONE NAT Gateway shared across all AZs instead of one per AZ.
  # This saves cost but is a single point of failure — acceptable for dev/test.
  single_nat_gateway = true

  # Automatically assign a public IP to any EC2 instance launched
  # in a public subnet, so it's reachable from the internet.
  map_public_ip_on_launch = true

  # General tags applied to all resources created by this module
  tags = {
    Terraform   = "true" # Marks resources as managed by Terraform
    Environment = "dev"  # Identifies this as a development environment
  }

  # Tag public subnets so that Kubernetes (EKS) knows to use them
  # for internet-facing load balancers (e.g., AWS ALB/NLB via the AWS Load Balancer Controller)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Tag private subnets so that Kubernetes (EKS) knows to use them
  # for internal load balancers that are only accessible within the VPC
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}