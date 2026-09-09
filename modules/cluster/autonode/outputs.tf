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
