#------------------------------------------------------------------------------
# AutoNode (Karpenter) Module Outputs
#------------------------------------------------------------------------------

output "karpenter_role_arn" {
  description = "ARN of the Karpenter controller IAM role."
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_policy_arn" {
  description = "ARN of the Karpenter controller IAM policy."
  value       = aws_iam_policy.karpenter.arn
}

output "rosa_enable_command" {
  description = "DEPRECATED: AutoNode is now enabled via Terraform auto_node block. This output is retained for backward compatibility."
  value       = ""
}

output "tagged_subnet_ids" {
  description = "Subnet IDs tagged with Karpenter discovery tags (empty in IAM-only mode)."
  value       = var.cluster_id != null ? var.private_subnet_ids : []
}
