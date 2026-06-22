# Admin Module Outputs

output "admin_id" {
  description = "Admin instance ID for SSM access"
  value       = aws_instance.admin.id
}

output "admin_instance_id" {
  description = "Admin instance ID for SSM access (deprecated, use admin_id)"
  value       = aws_instance.admin.id
}

output "admin_private_ip" {
  description = "Admin private IP"
  value       = aws_instance.admin.private_ip
}
