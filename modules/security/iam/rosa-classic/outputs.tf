#------------------------------------------------------------------------------
# IAM Roles Module Outputs - ROSA Classic
#
# Cluster-scoped IAM roles: each cluster has its own roles.
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

output "account_role_prefix" {
  description = "Prefix used for account IAM roles (defaults to cluster_name)."
  value       = local.account_role_prefix
}

output "operator_role_prefix" {
  description = "Prefix used for operator IAM roles (defaults to cluster_name)."
  value       = local.operator_role_prefix
}

output "oidc_config_id" {
  description = "ID of the OIDC configuration."
  value       = local.oidc_config_id
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL."
  value       = local.oidc_endpoint_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider."
  value       = var.create_oidc_config ? aws_iam_openid_connect_provider.this[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

output "oidc_managed" {
  description = "Whether the OIDC configuration is managed by Red Hat."
  value       = var.create_oidc_config ? var.managed_oidc : null
}

output "oidc_created" {
  description = "Whether the OIDC configuration was created by this module."
  value       = var.create_oidc_config
}

#------------------------------------------------------------------------------
# Account Roles (Cluster-Scoped)
#------------------------------------------------------------------------------

output "installer_role_arn" {
  description = "ARN of the installer role."
  value       = aws_iam_role.installer.arn
}

output "support_role_arn" {
  description = "ARN of the support role."
  value       = aws_iam_role.support.arn
}

output "control_plane_role_arn" {
  description = "ARN of the control plane role."
  value       = aws_iam_role.control_plane.arn
}

output "worker_role_arn" {
  description = "ARN of the worker role."
  value       = aws_iam_role.worker.arn
}

output "worker_instance_profile_name" {
  description = "Name of the worker instance profile."
  value       = aws_iam_instance_profile.worker.name
}

output "control_plane_instance_profile_name" {
  description = "Name of the control plane instance profile."
  value       = aws_iam_instance_profile.control_plane.name
}

# Combined outputs for easy reference
output "account_roles_arn" {
  description = "Map of account role names to ARNs."
  value = {
    "Installer"    = aws_iam_role.installer.arn
    "Support"      = aws_iam_role.support.arn
    "ControlPlane" = aws_iam_role.control_plane.arn
    "Worker"       = aws_iam_role.worker.arn
  }
}

#------------------------------------------------------------------------------
# Operator Roles (Cluster-Scoped)
#------------------------------------------------------------------------------

output "operator_roles" {
  description = "List of operator role ARNs (empty if create_operator_roles=false)."
  value       = [for role in aws_iam_role.operator : role.arn]
}

output "operator_role_names" {
  description = "List of operator role names (empty if create_operator_roles=false)."
  value       = [for role in aws_iam_role.operator : role.name]
}

output "operator_policies" {
  description = "List of operator policy ARNs (empty if create_operator_roles=false)."
  value       = [for policy in aws_iam_policy.operator : policy.arn]
}

output "operator_roles_ready" {
  description = "Indicates that operator roles have been created and propagated (or skipped if disabled)."
  value       = true
  depends_on  = [time_sleep.role_propagation]
}

output "create_operator_roles" {
  description = "Whether operator roles are managed by Terraform."
  value       = var.create_operator_roles
}

#------------------------------------------------------------------------------
# Ready Signals
#------------------------------------------------------------------------------

output "account_roles_ready" {
  description = "Indicates that account roles are available."
  value       = true
  depends_on = [
    aws_iam_role_policy.installer,
    aws_iam_role_policy.support,
    aws_iam_role_policy.control_plane,
    aws_iam_role_policy.worker
  ]
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "iam_summary" {
  description = "Summary of IAM configuration for this cluster."
  value = {
    cluster_name         = var.cluster_name
    account_role_prefix  = local.account_role_prefix
    operator_role_prefix = local.operator_role_prefix
    account_roles = {
      installer     = aws_iam_role.installer.arn
      support       = aws_iam_role.support.arn
      control_plane = aws_iam_role.control_plane.arn
      worker        = aws_iam_role.worker.arn
    }
    oidc = {
      config_id    = local.oidc_config_id
      endpoint_url = local.oidc_endpoint_url
      managed      = var.create_oidc_config ? var.managed_oidc : null
      created      = var.create_oidc_config
    }
    operator_roles_count = length(aws_iam_role.operator)
  }
}
