variable "bucket_name" {
  description = "S3 bucket name to upload the app into"
  type        = string
}

variable "app_dir" {
  description = "Absolute path to the local app directory to sync"
  type        = string
}

variable "upload_script" {
  description = "Absolute path to the upload-app.sh script"
  type        = string
}
