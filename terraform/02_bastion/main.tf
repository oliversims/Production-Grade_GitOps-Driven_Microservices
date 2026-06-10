resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_keypair" {
  key_name   = "bastion-key"
  public_key = tls_private_key.bastion_key.public_key_openssh
}

resource "local_file" "bastion_private_key" {
  content         = tls_private_key.bastion_key.private_key_pem
  filename        = "bastion-key.pem"
  file_permission = "0400"
}

resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

module "bastion_host" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name          = "bastion-host"
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.bastion_keypair.key_name
  monitoring    = true

  subnet_id                   = element(data.terraform_remote_state.vpc.outputs.public_subnets, 0)
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  # IAM role attached here — AWS CLI works without aws configure
  iam_instance_profile = aws_iam_instance_profile.bastion.name

  # On first boot: clone scripts from GitHub, then run install-tools.sh
  user_data = templatefile("${path.module}/scripts/user_data.sh.tpl", {
    github_private_key = tls_private_key.github_key.private_key_openssh
    github_public_key  = chomp(tls_private_key.github_key.public_key_openssh)
  })

  user_data_replace_on_change = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Role        = "bastion"
  }
}
