#------------------------------------------------------------------------------
# AWS EFS Storage Outputs
#------------------------------------------------------------------------------

output "efs_file_system_id" {
  description = "ID of the EFS file system."
  value       = aws_efs_file_system.this.id
}

output "efs_role_arn" {
  description = "ARN of the IAM role for the EFS CSI driver."
  value       = aws_iam_role.efs_csi.arn
}

output "efs_security_group_id" {
  description = "Security group ID for EFS mount targets."
  value       = aws_security_group.efs.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system."
  value       = aws_efs_file_system.this.dns_name
}
