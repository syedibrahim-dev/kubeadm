# Admin Module - Private kubectl management instance

# IAM Role for Admin Instance
resource "aws_iam_role" "admin_role" {
  name = "${var.admin_name}-role"

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
    Name = "${var.admin_name}-role"
  }
}

# IAM Policy for Admin Instance (SSM Parameter Store Read Access)
resource "aws_iam_role_policy" "admin_ssm_policy" {
  name = "${var.admin_name}-ssm-policy"
  role = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/k8s/*",
          "arn:aws:ssm:*::document/AWS-RunShellScript",
          "arn:aws:ec2:*:*:instance/*"
        ]
      }
    ]
  })
}

# IAM Policy for Stage 2 Terraform — argocd module creates ALB + registers NLB targets
resource "aws_iam_role_policy" "admin_terraform_policy" {
  name = "${var.admin_name}-terraform-policy"
  role = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # All EC2 reads — covers state refresh for VPC, compute, security, admin modules.
        # Wildcard avoids repeated one-by-one additions as new data sources are added.
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = ["*"]
      },
      {
        # EC2 writes — SG management for ALB security group (argocd module Stage 2)
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = ["*"]
      },
      {
        # Full ELBv2 — creates ALB, target groups, listeners; registers CCM NLB IPs
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = ["*"]
      },
      {
        # IAM reads — state refresh for admin module (role, policies, instance profile)
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = ["*"]
      },
      {
        # IAM writes — applied by Stage 1 (laptop), but needed if admin policy drifts
        # and Stage 2 needs to correct it in-place
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Attach AWS managed policy for SSM Session Manager
resource "aws_iam_role_policy_attachment" "admin_ssm_managed" {
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile for Admin Instance
resource "aws_iam_instance_profile" "admin_profile" {
  name = "${var.admin_name}-profile"
  role = aws_iam_role.admin_role.name
}

# Admin EC2 Instance (Private Subnet, SSM Access Only)
resource "aws_instance" "admin" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.admin_profile.name

  user_data = var.enable_auto_setup ? templatefile("${path.root}/scripts/admin-setup.sh", {
    aws_region         = var.aws_region
    control_plane_name = var.control_plane_name
    control_plane_ip   = var.control_plane_private_ip
    github_repo        = var.github_repo
    enable_auto_deploy = var.enable_auto_deploy
    worker_count       = var.worker_count
    k8s_version        = var.k8s_version
    terraform_version  = var.terraform_version
  }) : null

  tags = {
    Name = var.admin_name
  }

  depends_on = [var.nat_gateway_id]
}
