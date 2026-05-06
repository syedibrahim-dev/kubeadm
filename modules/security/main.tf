terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Security Groups Module

# Admin Instance Security Group
resource "aws_security_group" "admin_sg" {
  name        = var.admin_security_group_name
  description = "Security group for Admin kubectl management instance - SSM access only"
  vpc_id      = var.vpc_id

  # No inbound rules - access via AWS SSM Session Manager only

  # Allow all outbound traffic (for SSM agent, kubectl API access, downloading packages)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
    description = "Allow all outbound for SSM, kubectl, and package downloads"
  }

  tags = {
    Name = var.admin_security_group_name
  }
}

# Kubernetes Nodes Security Group
resource "aws_security_group" "k8s_nodes_sg" {
  name        = var.nodes_security_group_name
  description = "Security group for K8s control plane and worker nodes - SSM access only, no SSH"
  vpc_id      = var.vpc_id

  # Allow Kubernetes API access from Admin instance
  ingress {
    from_port       = var.k8s_api_port
    to_port         = var.k8s_api_port
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

  # Allow the full Kubernetes NodePort range from within the VPC.
  # CCM provisions the internal NLB and auto-assigns a NodePort for nginx
  # (no longer fixed at 30080). The NLB source IPs are always within the VPC
  # so restricting to vpc_cidr keeps this VPC-internal only.
  ingress {
    from_port   = var.nodeport_range.from_port
    to_port     = var.nodeport_range.to_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow K8s NodePort range from VPC CIDR (CCM-provisioned NLB to nginx)"
  }

  # Allow all outbound traffic (for SSM agent, downloading packages via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
    description = "Allow all outbound for SSM and package downloads"
  }

  tags = {
    Name                                        = var.nodes_security_group_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
