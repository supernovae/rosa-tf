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
