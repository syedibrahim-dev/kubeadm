# Latest Ubuntu 22.04 LTS (Jammy) AMI — Canonical account 099720109477.
# Pinned to hvm-ssd (not gp3) because the filter matches the original naming
# convention used when this cluster was first provisioned.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
