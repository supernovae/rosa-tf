#------------------------------------------------------------------------------
# OADP Resources Module Outputs
#------------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the S3 bucket for OADP backups."
  value       = aws_s3_bucket.oadp.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket for OADP backups."
  value       = aws_s3_bucket.oadp.arn
}

output "bucket_region" {
  description = "Region of the S3 bucket."
  value       = data.aws_region.current.id
}

output "role_arn" {
  description = "ARN of the IAM role for OADP."
  value       = aws_iam_role.oadp.arn
}

output "role_name" {
  description = "Name of the IAM role for OADP."
  value       = aws_iam_role.oadp.name
}

# ConfigMap contribution - values to pass to GitOps layer
output "gitops_config" {
  description = "Configuration values to add to the GitOps ConfigMap bridge."
  value = {
    oadp_bucket_name = aws_s3_bucket.oadp.id
    oadp_bucket_arn  = aws_s3_bucket.oadp.arn
    oadp_role_arn    = aws_iam_role.oadp.arn
    oadp_region      = data.aws_region.current.id
  }
}

output "ready" {
  description = "Indicates that OADP resources are ready."
  value       = true
  depends_on  = [time_sleep.role_propagation]
}
