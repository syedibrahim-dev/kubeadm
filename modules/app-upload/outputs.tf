output "trigger_hash" {
  description = "Hash of all app files — changes whenever any file is modified"
  value       = null_resource.upload_k8s_app.triggers["app_hash"]
}
