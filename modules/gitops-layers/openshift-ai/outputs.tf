#------------------------------------------------------------------------------
# OpenShift AI Resources Module - Outputs
#------------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the S3 bucket for RHOAI data storage."
  value       = var.create_s3 ? local.bucket_name : ""
}

output "bucket_arn" {
  description = "ARN of the S3 bucket for RHOAI data storage."
  value       = var.create_s3 ? local.bucket_arn : ""
}

output "bucket_region" {
  description = "Region of the S3 bucket."
  value       = var.create_s3 ? var.aws_region : ""
}

output "role_arn" {
  description = "ARN of the IAM role for RHOAI workloads."
  value       = aws_iam_role.rhoai.arn
}

output "role_name" {
  description = "Name of the IAM role for RHOAI workloads."
  value       = aws_iam_role.rhoai.name
}

output "s3_endpoint" {
  description = "S3 endpoint URL for RHOAI data connections."
  value       = var.create_s3 ? local.s3_endpoint : ""
}

output "gitops_config" {
  description = "Configuration values passed to the operator module for OpenShift AI layer."
  value = {
    bucket_name   = var.create_s3 ? local.bucket_name : ""
    bucket_region = var.create_s3 ? var.aws_region : ""
    role_arn      = aws_iam_role.rhoai.arn
    s3_endpoint   = var.create_s3 ? local.s3_endpoint : ""
    is_govcloud   = var.is_govcloud
  }
}

output "ready" {
  description = "Indicates that OpenShift AI AWS resources are ready."
  value       = true
  depends_on  = [time_sleep.role_propagation]
}
