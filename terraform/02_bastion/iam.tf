# IAM role for the bastion EC2 instance.
# The instance gets AWS credentials automatically — no "aws configure" needed.

# Step 1: Create a role that EC2 is allowed to use
resource "aws_iam_role" "bastion" {
  name = "bastion-host-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "bastion-host-role"
    Environment = "dev"
    Terraform   = "true"
  }
}

# Step 2: Allow the bastion to call EKS APIs (needed for aws eks update-kubeconfig)
resource "aws_iam_role_policy" "bastion_eks" {
  name = "bastion-eks-api"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = "*"
      }
    ]
  })
}

# Step 3: EKS, EC2, ELB, Route53, etc. — does not include iam:CreatePolicy or iam:CreateRole
resource "aws_iam_role_policy_attachment" "bastion_poweruser" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Step 4: IAM policies and roles — required for install-lbc.sh and eksctl iamserviceaccount
resource "aws_iam_role_policy_attachment" "bastion_iam" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

# Step 5: Attach the role to EC2 via an instance profile
resource "aws_iam_instance_profile" "bastion" {
  name = "bastion-host-profile"
  role = aws_iam_role.bastion.name

  tags = {
    Name        = "bastion-host-profile"
    Environment = "dev"
    Terraform   = "true"
  }
}
