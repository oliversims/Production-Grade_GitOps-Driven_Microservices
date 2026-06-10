terraform {
  required_version = ">= 1.14.0"

  cloud {
    organization = "Devops-terraform-backend"

    workspaces {
      name = "Devops-terraform-vpc"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.42.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
