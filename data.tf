# Data Sources

# Get Current AWS Account Identity (for unique bucket naming)
data "aws_caller_identity" "current" {}

# Get Available Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Find the Latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
