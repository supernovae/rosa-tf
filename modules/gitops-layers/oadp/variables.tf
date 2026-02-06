#------------------------------------------------------------------------------
# OADP Resources Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    OIDC provider endpoint URL (without https:// prefix).
    Get from: module.iam_roles.oidc_endpoint_url
  EOT
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for S3 bucket encryption. If null, uses AES256."
  default     = null
}

variable "backup_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain backups in S3. 
    Set to 0 to disable lifecycle rules (manual cleanup).
    Recommended: 30-90 days for regular backups.
  EOT
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 0
    error_message = "Backup retention days must be 0 or greater."
  }
}

variable "iam_role_path" {
  type        = string
  description = "Path for the IAM role."
  default     = "/"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
