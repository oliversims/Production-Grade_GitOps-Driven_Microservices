terraform {
  required_version = ">= 1.14.0"

  cloud {
    organization = "Devops-terraform-backend"

    workspaces {
      name = "Devops-terraform-bastion"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.42.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
