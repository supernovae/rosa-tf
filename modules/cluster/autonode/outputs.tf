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
  description = "Command to enable AutoNode on the cluster (run after terraform apply)."
  value       = "rosa edit cluster -c ${var.cluster_id} --autonode=enabled --autonode-iam-role-arn=${aws_iam_role.karpenter.arn}"
}

output "tagged_subnet_ids" {
  description = "Subnet IDs tagged with Karpenter discovery tags."
  value       = var.private_subnet_ids
}
