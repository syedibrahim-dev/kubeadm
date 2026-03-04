# Security Module Outputs

output "admin_sg_id" {
  description = "Admin instance security group ID"
  value       = aws_security_group.admin_sg.id
}

output "k8s_nodes_sg_id" {
  description = "Kubernetes nodes security group ID"
  value       = aws_security_group.k8s_nodes_sg.id
}
