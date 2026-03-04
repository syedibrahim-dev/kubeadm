# S3 Module - Stores k8s-app for automated delivery to admin instance

resource "aws_s3_bucket" "k8s_app" {
  bucket        = "k8s-app-${var.account_id}-${var.aws_region}"
  force_destroy = true

  tags = {
    Name = "k8s-app"
  }
}

resource "aws_s3_bucket_versioning" "k8s_app" {
  bucket = aws_s3_bucket.k8s_app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "k8s_app" {
  bucket = aws_s3_bucket.k8s_app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "k8s_app" {
  bucket                  = aws_s3_bucket.k8s_app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
