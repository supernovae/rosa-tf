#------------------------------------------------------------------------------
# Monitoring Resources Module Outputs
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# S3 Bucket
#------------------------------------------------------------------------------

output "loki_bucket_name" {
  description = "Name of the S3 bucket for Loki log storage."
  value       = aws_s3_bucket.loki.id
}

output "loki_bucket_arn" {
  description = "ARN of the S3 bucket for Loki log storage."
  value       = aws_s3_bucket.loki.arn
}

output "loki_bucket_region" {
  description = "Region of the S3 bucket."
  value       = var.aws_region
}

#------------------------------------------------------------------------------
# IAM Role
#------------------------------------------------------------------------------

output "loki_role_arn" {
  description = "ARN of the IAM role for Loki."
  value       = aws_iam_role.loki.arn
}

output "loki_role_name" {
  description = "Name of the IAM role for Loki."
  value       = aws_iam_role.loki.name
}

#------------------------------------------------------------------------------
# S3 Endpoint
#------------------------------------------------------------------------------

output "s3_endpoint" {
  description = <<-EOT
    S3 endpoint URL for Loki configuration.
    GovCloud uses region-specific endpoints.
  EOT
  value       = local.s3_endpoint
}

output "logging_namespace" {
  description = "Namespace where logging components are deployed."
  value       = local.loki_namespace
}

#------------------------------------------------------------------------------
# Retention Configuration
#------------------------------------------------------------------------------

output "log_retention_days" {
  description = "Configured log retention in days."
  value       = var.log_retention_days
}

output "log_retention_hours" {
  description = "Configured log retention in hours (for Loki config)."
  value       = var.log_retention_days * 24
}

#------------------------------------------------------------------------------
# Summary for GitOps ConfigMap
#------------------------------------------------------------------------------

output "gitops_config" {
  description = "Configuration values to pass to GitOps layer."
  value = {
    bucket_name       = aws_s3_bucket.loki.id
    bucket_region     = var.aws_region
    role_arn          = aws_iam_role.loki.arn
    s3_endpoint       = local.s3_endpoint
    retention_days    = var.log_retention_days
    retention_hours   = var.log_retention_days * 24
    is_govcloud       = var.is_govcloud
    openshift_version = var.openshift_version
  }
}
