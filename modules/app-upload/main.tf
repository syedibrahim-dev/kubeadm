# App Upload Module - Syncs k8s-app to S3 on every terraform apply.
# Re-triggers automatically when any file inside the app directory changes.

resource "null_resource" "upload_k8s_app" {
  triggers = {
    bucket   = var.bucket_name
    app_hash = sha256(join("", [
      for f in sort(fileset(var.app_dir, "**/*")) :
      filesha256("${var.app_dir}/${f}")
    ]))
  }

  provisioner "local-exec" {
    command = "bash ${var.upload_script} ${var.bucket_name}"
  }
}
