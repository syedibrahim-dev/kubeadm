# Security Groups Module

# Admin Instance Security Group
resource "aws_security_group" "admin_sg" {
  name        = "k8s-admin-sg"
  description = "Security group for Admin kubectl management instance - SSM access only"
  vpc_id      = var.vpc_id

  # No inbound rules - access via AWS SSM Session Manager only

  # Allow all outbound traffic (for SSM agent, kubectl API access, downloading packages)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound for SSM, kubectl, and package downloads"
  }

  tags = {
    Name = "k8s-admin-sg"
  }
}

# Kubernetes Nodes Security Group
resource "aws_security_group" "k8s_nodes_sg" {
  name        = "k8s-nodes-sg"
  description = "Security group for K8s control plane and worker nodes - SSM access only, no SSH"
  vpc_id      = var.vpc_id

  # Allow Kubernetes API access from Admin instance
  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.admin_sg.id]
    description     = "Allow K8s API access from Admin instance"
  }

  # Allow all traffic between K8s nodes (control plane <-> worker communication)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all traffic between K8s nodes"
  }

  # Allow NLB → ingress-nginx HTTP NodePort
  # NLB does not have a security group; source IPs are client IPs (preserved by NLB)
  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow NLB traffic to ingress-nginx HTTP NodePort"
  }

  # Allow NLB → ArgoCD server NodePort
  ingress {
    from_port   = 30082
    to_port     = 30082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow NLB traffic to ArgoCD NodePort"
  }

  # Allow all outbound traffic (for SSM agent, downloading packages via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound for SSM and package downloads"
  }

  tags = {
    Name = "k8s-nodes-sg"
  }
}
