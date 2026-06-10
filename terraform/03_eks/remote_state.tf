data "terraform_remote_state" "vpc" {
  backend = "remote"

  config = {
    organization = "Devops-terraform-backend"

    workspaces = {
      name = "Devops-terraform-vpc"
    }
  }
}

data "terraform_remote_state" "bastion" {
  backend = "remote"

  config = {
    organization = "Devops-terraform-backend"

    workspaces = {
      name = "Devops-terraform-bastion"
    }
  }
}
