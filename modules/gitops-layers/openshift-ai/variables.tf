#------------------------------------------------------------------------------
# OpenShift AI Resources Module - Variables
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Inputs
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    OIDC provider endpoint URL (without https:// prefix).
    Used for RHOAI workload IRSA trust policy.
  EOT
}

variable "aws_region" {
  type        = string
  description = <<-EOT
    AWS region for S3 bucket and endpoint configuration.
    GovCloud: us-gov-west-1 or us-gov-east-1
    Commercial: us-east-1, us-west-2, etc.
  EOT
}

#------------------------------------------------------------------------------
# Feature Toggles
#------------------------------------------------------------------------------

variable "create_s3" {
  type        = bool
  description = "Create S3 bucket for AI Pipelines artifact storage."
  default     = false
}

variable "create_ecr_policy" {
  type        = bool
  description = "Attach ECR push/pull policy to the RHOAI IAM role for OCI model images."
  default     = false
}

variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the ECR repository for OCI model images."
  default     = ""
}

#------------------------------------------------------------------------------
# S3 Configuration
#------------------------------------------------------------------------------

variable "s3_bucket_name" {
  type        = string
  description = <<-EOT
    Name for the RHOAI S3 bucket. Must be globally unique.
    If not provided, defaults to: {cluster_name}-rhoai-data
  EOT
  default     = ""
}

variable "data_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain pipeline artifacts and model data in S3.
    Controls S3 lifecycle rules for object expiration.
    Set to 0 to disable automatic expiration.
  EOT
  default     = 0

  validation {
    condition     = var.data_retention_days >= 0 && var.data_retention_days <= 3650
    error_message = "Data retention days must be between 0 (disabled) and 3650 (10 years)."
  }
}

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for S3 bucket encryption. If null, uses AES256."
  default     = null
}

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

variable "iam_role_path" {
  type        = string
  description = "Path for the IAM role."
  default     = "/"
}

#------------------------------------------------------------------------------
# Environment Detection
#------------------------------------------------------------------------------

variable "is_govcloud" {
  type        = bool
  description = <<-EOT
    Whether this is a GovCloud deployment.
    Affects S3 endpoint URL format and partition for IAM ARNs.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
