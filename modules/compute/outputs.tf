# Compute Module Outputs

output "control_plane_id" {
  description = "Control plane instance ID"
  value       = aws_instance.control_plane.id
}

output "control_plane_name" {
  description = "Control plane name for Parameter Store paths"
  value       = var.control_plane_name
}

output "control_plane_private_ip" {
  description = "Control plane private IP"
  value       = aws_instance.control_plane.private_ip
}

output "worker_id" {
  description = "Worker instance IDs"
  value       = aws_instance.worker[*].id
}

output "worker_private_ip" {
  description = "Worker private IPs"
  value       = aws_instance.worker[*].private_ip
}

output "worker_count" {
  description = "Number of worker nodes"
  value       = var.worker_count
}
