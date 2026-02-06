#------------------------------------------------------------------------------
# ROSA HCP Account Layer - Outputs
#
# These outputs provide the role ARNs needed by HCP clusters.
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

output "account_role_prefix" {
  description = "Prefix used for account IAM roles."
  value       = module.hcp_account_roles.account_role_prefix
}

output "installer_role_arn" {
  description = "ARN of the shared installer role."
  value       = module.hcp_account_roles.installer_role_arn
}

output "support_role_arn" {
  description = "ARN of the shared support role."
  value       = module.hcp_account_roles.support_role_arn
}

output "worker_role_arn" {
  description = "ARN of the shared worker role."
  value       = module.hcp_account_roles.worker_role_arn
}

output "account_roles_arn" {
  description = "Map of account role names to ARNs."
  value       = module.hcp_account_roles.account_roles_arn
}

output "worker_instance_profile_name" {
  description = "Name of the worker instance profile."
  value       = module.hcp_account_roles.worker_instance_profile_name
}

#------------------------------------------------------------------------------
# Role Names (for cluster layer discovery)
#------------------------------------------------------------------------------

output "installer_role_name" {
  description = "Name of the installer role (for discovery)."
  value       = module.hcp_account_roles.installer_role_name
}

output "support_role_name" {
  description = "Name of the support role (for discovery)."
  value       = module.hcp_account_roles.support_role_name
}

output "worker_role_name" {
  description = "Name of the worker role (for discovery)."
  value       = module.hcp_account_roles.worker_role_name
}

#------------------------------------------------------------------------------
# Usage Instructions
#------------------------------------------------------------------------------

output "usage_instructions" {
  description = "Instructions for using these account roles with HCP clusters."
  value       = module.hcp_account_roles.usage_instructions
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "account_summary" {
  description = "Summary of HCP account configuration."
  value       = module.hcp_account_roles.account_summary
}
