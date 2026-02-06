#------------------------------------------------------------------------------
# ROSA HCP Account Roles Module - Outputs
#
# These outputs provide the ARNs needed by HCP clusters to reference
# the shared account roles.
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

output "account_role_prefix" {
  description = "Prefix used for account IAM roles."
  value       = var.account_role_prefix
}

output "installer_role_arn" {
  description = "ARN of the shared installer role."
  value       = aws_iam_role.account_role[0].arn
}

output "support_role_arn" {
  description = "ARN of the shared support role."
  value       = aws_iam_role.account_role[1].arn
}

output "worker_role_arn" {
  description = "ARN of the shared worker role."
  value       = aws_iam_role.account_role[2].arn
}

output "worker_instance_profile_name" {
  description = "Name of the worker instance profile."
  value       = aws_iam_instance_profile.worker.name
}

output "account_roles_arn" {
  description = "Map of account role names to ARNs."
  value = {
    "Installer" = aws_iam_role.account_role[0].arn
    "Support"   = aws_iam_role.account_role[1].arn
    "Worker"    = aws_iam_role.account_role[2].arn
  }
}

output "account_roles_ready" {
  description = "Indicates that account roles are available (after propagation delay)."
  value       = time_sleep.iam_propagation.id
}

#------------------------------------------------------------------------------
# Role Names (for discovery by cluster layer)
#------------------------------------------------------------------------------

output "installer_role_name" {
  description = "Name of the installer role (for discovery)."
  value       = local.installer_role_name
}

output "support_role_name" {
  description = "Name of the support role (for discovery)."
  value       = local.support_role_name
}

output "worker_role_name" {
  description = "Name of the worker role (for discovery)."
  value       = local.worker_role_name
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "account_summary" {
  description = "Summary of HCP account roles configuration."
  value = {
    account_role_prefix = var.account_role_prefix
    roles = {
      installer = {
        name = local.installer_role_name
        arn  = aws_iam_role.account_role[0].arn
      }
      support = {
        name = local.support_role_name
        arn  = aws_iam_role.account_role[1].arn
      }
      worker = {
        name = local.worker_role_name
        arn  = aws_iam_role.account_role[2].arn
      }
    }
    instance_profile = aws_iam_instance_profile.worker.name
    kms_enabled      = local.enable_kms
  }
}

#------------------------------------------------------------------------------
# Usage Instructions
#------------------------------------------------------------------------------

output "usage_instructions" {
  description = "Instructions for using these account roles with HCP clusters."
  value       = <<-EOT
    HCP Account Roles Created Successfully!
    
    These roles can be used by all ROSA HCP clusters in this account.
    
    To create an HCP cluster referencing these roles:
    
    Option 1 - Terraform (recommended):
      Set in your cluster environment:
        create_account_roles = false
        # Roles will be auto-discovered using prefix: ${var.account_role_prefix}
    
    Option 2 - ROSA CLI:
      rosa create cluster --hosted-cp \
        --role-arn ${aws_iam_role.account_role[0].arn} \
        --support-role-arn ${aws_iam_role.account_role[1].arn} \
        --worker-role-arn ${aws_iam_role.account_role[2].arn}
    
    Role ARNs:
      Installer: ${aws_iam_role.account_role[0].arn}
      Support:   ${aws_iam_role.account_role[1].arn}
      Worker:    ${aws_iam_role.account_role[2].arn}
  EOT
}
