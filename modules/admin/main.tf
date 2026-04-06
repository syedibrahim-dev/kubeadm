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
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/k8s/*"
      }
    ]
  })
}

# IAM Policy for Admin Instance (S3 Read Access)
resource "aws_iam_role_policy" "admin_s3_policy" {
  name = "${var.admin_name}-s3-policy"
  role = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
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
    aws_region           = var.aws_region
    control_plane_name   = var.control_plane_name
    control_plane_ip     = var.control_plane_private_ip
    s3_bucket_name       = var.s3_bucket_name
    enable_auto_deploy   = var.enable_auto_deploy
    worker_count         = var.worker_count
  }) : null

  tags = {
    Name = var.admin_name
  }

  depends_on = [var.nat_gateway_id]
}
