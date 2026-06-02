# -------------------------------------------------------
# TLS KEY GENERATION: Create a new RSA private/public key pair
# -------------------------------------------------------
# Generates a 4096-bit RSA key pair entirely within Terraform.
# The public key will be uploaded to AWS, and the private key
# will be saved locally so you can SSH into the bastion host.
# NOTE: The private key is stored in Terraform state — treat it as sensitive.
resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096 # 4096-bit is stronger than the default 2048-bit
}

# -------------------------------------------------------
# AWS KEY PAIR: Register the public key with AWS
# -------------------------------------------------------
# Uploads the generated public key to AWS so it can be
# injected into EC2 instances at launch, enabling SSH access
# using the corresponding private key saved locally below.
resource "aws_key_pair" "bastion_keypair" {
  key_name   = "bastion-key"
  public_key = tls_private_key.bastion_key.public_key_openssh # OpenSSH format required by AWS
}

# -------------------------------------------------------
# LOCAL FILE: Save the private key to your local machine
# -------------------------------------------------------
# Writes the private key to a .pem file so you can use it
# with SSH to connect to the bastion host.
# file_permission = "0400" means read-only by the owner —
# this is required by SSH, which refuses keys that are too permissive.
resource "local_file" "bastion_private_key" {
  content         = tls_private_key.bastion_key.private_key_pem
  filename        = "bastion-key.pem"
  file_permission = "0400" # Owner read-only — SSH will reject the key without this
}

# -------------------------------------------------------
# SECURITY GROUP: Control traffic to/from the Bastion Host
# -------------------------------------------------------
# Attaches to the VPC created by the vpc module above.
# Only allows SSH inbound from YOUR current public IP,
# and allows all outbound traffic so the bastion can
# reach private instances inside the VPC.
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = module.vpc.vpc_id # Attach to the VPC created by the vpc module

  # INBOUND: Allow SSH (port 22) only from your current public IP.
  # Uses the dynamic IP fetched earlier by data.http.my_ip.
  # /32 means exactly one IP address (your IP only — no one else can SSH in).
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"] # Dynamically whitelists only your IP
  }

  # OUTBOUND: Allow all outbound traffic on any port/protocol.
  # Needed so the bastion can SSH into private instances
  # and reach the internet for updates, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 means ALL protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic to anywhere
  }

  tags = {
    Name = "bastion-sg"
  }
}

# -------------------------------------------------------
# MODULE: Bastion Host — A public-facing EC2 jump server
# -------------------------------------------------------
# A bastion host (also called a jump box) is a hardened EC2
# instance placed in a public subnet. You SSH into it first,
# then use it as a stepping stone to reach private instances
# that have no direct internet access.
# Uses the official Terraform AWS EC2 Instance module.
module "bastion_host" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name          = "bastion-host"
  ami           = data.aws_ami.ubuntu.id                # Uses the latest Ubuntu 22.04 AMI looked up earlier
  instance_type = "t3.micro"                            # Small, cost-effective instance — bastion doesn't need much power
  key_name      = aws_key_pair.bastion_keypair.key_name # Attach the key pair created above
  monitoring    = true                                  # Enable detailed CloudWatch monitoring

  # Place the bastion in the FIRST public subnet of the VPC.
  # element(..., 0) picks the first item from the list of public subnet IDs.
  subnet_id              = element(module.vpc.public_subnets, 0)
  vpc_security_group_ids = [aws_security_group.bastion_sg.id] # Attach the security group above

  # Give the bastion a public IP so it's reachable from the internet via SSH.
  associate_public_ip_address = true

  tags = {
    Terraform   = "true"    # Marks this as Terraform-managed
    Environment = "dev"     # Development environment
    Role        = "bastion" # Identifies the purpose of this instance
  }
}