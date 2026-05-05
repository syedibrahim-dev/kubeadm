terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Compute Module - Kubernetes Nodes

# IAM Role for Control Plane
resource "aws_iam_role" "control_plane_role" {
  name = "${var.control_plane_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.control_plane_name}-role"
  }
}

# IAM Policy for Control Plane — CCM (node lifecycle + NLB provisioning)
# CCM: node taints, labels, and Service type=LoadBalancer (NLB) management
resource "aws_iam_role_policy" "control_plane_ccm_policy" {
  name = "${var.control_plane_name}-ccm-policy"
  role = aws_iam_role.control_plane_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CCM — node lifecycle management
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcs",
          "ec2:DescribeInternetGateways",
          "ec2:CreateRoute",
          "ec2:DeleteRoute"
        ]
        Resource = ["*"]
      },
      {
        # CCM — NLB lifecycle for Service type=LoadBalancer
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTags",
          "iam:CreateServiceLinkedRole",
          "tag:GetResources"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# IAM Policy for Control Plane (SSM Write)
resource "aws_iam_role_policy" "control_plane_ssm_policy" {
  name = "${var.control_plane_name}-ssm-policy"
  role = aws_iam_role.control_plane_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/k8s/${var.control_plane_name}/join-command",
          "arn:aws:ssm:*:*:parameter/k8s/${var.control_plane_name}/kubeconfig"
        ]
      }
    ]
  })
}

# Attach AWS managed policy for SSM Session Manager
resource "aws_iam_role_policy_attachment" "control_plane_ssm_managed" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile for Control Plane
resource "aws_iam_instance_profile" "control_plane_profile" {
  name = "${var.control_plane_name}-profile"
  role = aws_iam_role.control_plane_role.name
}

# IAM Role for Worker Nodes
resource "aws_iam_role" "worker_role" {
  name = "${var.worker_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.worker_name}-role"
  }
}

# IAM Policy for Worker Nodes — EC2 describe permissions required by CCM for
# node registration (region/zone labels). Workers do NOT run CCM so they need
# no load balancer permissions.
resource "aws_iam_role_policy" "worker_ccm_policy" {
  name = "${var.worker_name}-ccm-policy"
  role = aws_iam_role.worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# IAM Policy for Worker Nodes (SSM Read)
resource "aws_iam_role_policy" "worker_ssm_policy" {
  name = "${var.worker_name}-ssm-policy"
  role = aws_iam_role.worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/k8s/${var.control_plane_name}/join-command"
      }
    ]
  })
}

# Attach AWS managed policy for SSM Session Manager
resource "aws_iam_role_policy_attachment" "worker_ssm_managed" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile for Worker Nodes
resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.worker_name}-profile"
  role = aws_iam_role.worker_role.name
}

# Control Plane Node (Private)
resource "aws_instance" "control_plane" {
  ami                    = var.ami_id
  instance_type          = var.control_plane_instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  private_ip             = var.control_plane_private_ip
  iam_instance_profile   = aws_iam_instance_profile.control_plane_profile.name

  # CRITICAL for Calico CNI to work!
  source_dest_check = false

  root_block_device {
    volume_size = var.volume_size
    volume_type = var.root_volume_type
  }

  # Automatic Kubernetes setup
  user_data = var.enable_auto_setup ? templatefile("${path.root}/scripts/control-plane-setup.sh", {
    control_plane_ip   = var.control_plane_private_ip
    control_plane_name = var.control_plane_name
    aws_region         = var.aws_region
    k8s_version        = var.k8s_version
    pod_subnet_cidr    = var.pod_subnet_cidr
    ccm_version        = var.ccm_version
    cluster_name       = var.cluster_name
  }) : null

  tags = {
    Name                                        = var.control_plane_name
    Role                                        = "control-plane"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Worker Node (Private)
resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = var.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.worker_profile.name

  # CRITICAL for Calico CNI to work!
  source_dest_check = false

  root_block_device {
    volume_size = var.volume_size
    volume_type = var.root_volume_type
  }

  # Automatic Kubernetes setup
  user_data = var.enable_auto_setup ? templatefile("${path.root}/scripts/worker-setup.sh", {
    control_plane_ip   = var.control_plane_private_ip
    control_plane_name = var.control_plane_name
    aws_region         = var.aws_region
    k8s_version        = var.k8s_version
  }) : null

  tags = {
    Name                                        = "${var.worker_name}-${count.index + 1}"
    Role                                        = "worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
