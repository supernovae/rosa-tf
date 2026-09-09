#------------------------------------------------------------------------------
# OADP Resources Module Outputs
#------------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the S3 bucket for OADP backups."
  value       = local.bucket_name
  depends_on  = [aws_cloudformation_stack.oadp_bucket]
}

output "bucket_arn" {
  description = "ARN of the S3 bucket for OADP backups."
  value       = local.bucket_arn
}

output "bucket_region" {
  description = "Region of the S3 bucket."
  value       = data.aws_region.current.region
}

output "role_arn" {
  description = "ARN of the IAM role for OADP."
  value       = aws_iam_role.oadp.arn
  depends_on  = [time_sleep.role_propagation]
}

output "role_name" {
  description = "Name of the IAM role for OADP."
  value       = aws_iam_role.oadp.name
}

# Values passed to the operator module for layer configuration
output "gitops_config" {
  description = "Configuration values passed to the operator module for OADP layer."
  value = {
    oadp_bucket_name = local.bucket_name
    oadp_bucket_arn  = local.bucket_arn
    oadp_role_arn    = aws_iam_role.oadp.arn
    oadp_region      = data.aws_region.current.region
  }
}

output "ready" {
  description = "Indicates that OADP resources are ready."
  value       = true
  depends_on  = [time_sleep.role_propagation, aws_cloudformation_stack.oadp_bucket]
}
