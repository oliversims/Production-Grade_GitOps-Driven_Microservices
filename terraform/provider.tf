terraform {
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

terraform {
  required_version = "1.15.5"

  cloud {
    
    organization = "Devopsdock-terraform"

    workspaces {
      name = "Devopsdock-terraform-backend"
    }
  }
}

