#------------------------------------------------------------------------------
# Monitoring Resources Module Variables
#
# This module creates AWS resources for OpenShift monitoring and logging:
# - S3 bucket for Loki log storage
# - IAM role with OIDC trust for Loki service account
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
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

variable "aws_region" {
  type        = string
  description = <<-EOT
    AWS region for S3 bucket and endpoint configuration.
    GovCloud: us-gov-west-1 or us-gov-east-1
    Commercial: us-east-1, us-west-2, etc.
  EOT
}

#------------------------------------------------------------------------------
# S3 Configuration
#------------------------------------------------------------------------------

variable "s3_bucket_name" {
  type        = string
  description = <<-EOT
    Name for the Loki S3 bucket. Must be globally unique.
    If not provided, defaults to: {cluster_name}-loki-logs
  EOT
  default     = ""
}

#------------------------------------------------------------------------------
# Retention Configuration
#------------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain logs in S3 and Loki.
    This controls both:
    - S3 lifecycle rules (object expiration)
    - Loki compactor retention (chunk deletion)
    
    Recommended values:
    - Development: 7 days
    - Production: 30 days
    - Compliance: 90-365 days
  EOT
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
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
    Affects:
    - S3 endpoint URL format
    - Logging API version selection
    - Partition for IAM ARNs
  EOT
  default     = false
}

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for API compatibility.
    - 4.16.x: Uses logging.openshift.io/v1 API
    - 4.17+: Uses observability.openshift.io/v1 API
  EOT
  default     = "4.20"
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
