# VPC Module - Network Infrastructure

# Custom VPC for Private Kubernetes Cluster
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                  = "k8s-private-vpc"
    "kubernetes.io/cluster/kubeadm-cluster" = "owned"
  }
}

# Internet Gateway for Public Subnet
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

# Public Subnet (for Bastion and NAT Gateway)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name                                  = "k8s-public-subnet"
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/kubeadm-cluster" = "owned"
  }
}

# Private Subnet (for K8s nodes)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name                                  = "k8s-private-subnet"
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/kubeadm-cluster" = "owned"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "k8s-nat-eip"
  }

  depends_on = [aws_internet_gateway.k8s_igw]
}

# NAT Gateway (allows private instances to access internet)
resource "aws_nat_gateway" "k8s_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "k8s-nat-gateway"
  }

  depends_on = [aws_internet_gateway.k8s_igw]
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s-public-rt"
  }
}

# Route Table for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.k8s_nat.id
  }

  tags = {
    Name = "k8s-private-rt"
  }
}

# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate Private Route Table with Private Subnet
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
