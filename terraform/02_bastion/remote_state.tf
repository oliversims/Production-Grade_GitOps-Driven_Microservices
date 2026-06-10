data "terraform_remote_state" "vpc" {
  backend = "remote"

  config = {
    organization = "Devops-terraform-backend"

    workspaces = {
      name = "Devops-terraform-vpc"
    }
  }
}
