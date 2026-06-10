###############################################################################
# variables.tf — Input variables
###############################################################################

variable "location" {
  description = "Azure region for all resources. Must be an allowed region for your Student account."
  type        = string
  default     = "switzerlandnorth"
}

variable "environment" {
  description = "Environment label used in resource names (dev / prod)."
  type        = string
  default     = "prod"
}

variable "db_admin_user" {
  description = "Administrator login name for the PostgreSQL Flexible Server."
  type        = string
  default     = "giteaadmin"
}

variable "db_admin_password" {
  description = <<-EOT
    Administrator password for PostgreSQL.
    Never hard-code this value. Supply it via:
      export TF_VAR_db_admin_password="<your-secure-password>"
  EOT
  type        = string
  sensitive   = true
}

variable "gitea_image_tag" {
  description = "Gitea Docker image tag used for the initial App Service container configuration."
  type        = string
  default     = "1.22"
}
