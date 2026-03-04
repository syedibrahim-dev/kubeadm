# Bastion Host Module

# Bastion Host (Jump Server for SSH Access)
resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true

  tags = {
    Name = "k8s-bastion"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y curl wget
              
              # Install kubectl on bastion for easier cluster management
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
              EOF
}

# Elastic IP for Bastion (Static Public IP)
resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = {
    Name = "k8s-bastion-eip"
  }
}
