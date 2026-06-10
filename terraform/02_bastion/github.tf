# GitHub SSH key — kept in Terraform state so the same key is reused
# when the bastion is destroyed and recreated (add to GitHub once).

resource "tls_private_key" "github_key" {
  algorithm = "ED25519"
}

resource "local_file" "github_private_key" {
  content         = tls_private_key.github_key.private_key_openssh
  filename        = "${path.module}/github-key.pem"
  file_permission = "0600"
}

resource "local_file" "github_public_key" {
  content         = tls_private_key.github_key.public_key_openssh
  filename        = "${path.module}/github-key.pub"
  file_permission = "0644"
}
