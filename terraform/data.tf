# -------------------------------------------------------
# DATA SOURCE: Fetch your current public IP address
# -------------------------------------------------------
# Makes an HTTP GET request to AWS's IP-check service,
# which returns your current public IP as plain text.
# This is commonly used to dynamically whitelist only YOUR
# IP in security group rules, instead of hardcoding it.
# Usage: "${chomp(data.http.my_ip.response_body)}/32"
# (chomp removes the trailing newline from the response)
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

# -------------------------------------------------------
# DATA SOURCE: Look up the latest Ubuntu 22.04 AMI
# -------------------------------------------------------
# Queries AWS for the most recent Ubuntu 22.04 (Jammy) AMI
# that matches both filters below, owned by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true # Always grab the latest matching AMI

  # Filter 1: Match by AMI name pattern
  # The wildcard (*) at the end matches any patch/build version
  # of Ubuntu 22.04 Jammy on HVM with SSD storage.
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  # Filter 2: Only return AMIs that use Hardware Virtual Machine (HVM)
  # HVM is the modern virtualization type required for most instance types.
  # (The older alternative was "paravirtual", which is largely deprecated)
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical's official AWS account ID — ensures we only get official Ubuntu images
}