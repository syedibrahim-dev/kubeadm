output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.k8s_app.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.k8s_app.arn
}
