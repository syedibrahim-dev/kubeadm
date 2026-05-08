# Common tags applied to every AWS resource in this project.
# Modules receive these via var.tags and merge them with resource-specific tags.
locals {
  common_tags = {
    Project   = var.core.cluster_name
    ManagedBy = "terraform"
  }
}
