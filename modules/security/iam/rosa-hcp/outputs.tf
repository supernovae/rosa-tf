#------------------------------------------------------------------------------
# ROSA HCP IAM Module Outputs
#
# Account role ARNs are resolved from: created > discovered > explicit
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Account Role Configuration
#------------------------------------------------------------------------------

output "create_account_roles" {
  description = "Whether account roles were created by this module."
  value       = var.create_account_roles
}

output "account_role_prefix" {
  description = "Prefix used for account roles."
  value       = var.account_role_prefix
}

#------------------------------------------------------------------------------
# Account Role ARNs
#------------------------------------------------------------------------------

output "installer_role_arn" {
  description = "ARN of the installer role."
  value       = time_sleep.iam_propagation.id != "" ? local.installer_role_arn : local.installer_role_arn
}

output "support_role_arn" {
  description = "ARN of the support role."
  value       = time_sleep.iam_propagation.id != "" ? local.support_role_arn : local.support_role_arn
}

output "worker_role_arn" {
  description = "ARN of the worker role."
  value       = time_sleep.iam_propagation.id != "" ? local.worker_role_arn : local.worker_role_arn
}

#------------------------------------------------------------------------------
# OIDC Configuration
#------------------------------------------------------------------------------

output "oidc_config_id" {
  description = "OIDC configuration ID for the cluster."
  value       = time_sleep.iam_propagation.id != "" ? local.oidc_config_id : local.oidc_config_id
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
# Operator Roles (Per-Cluster)
#------------------------------------------------------------------------------

output "operator_role_prefix" {
  description = "Prefix used for operator roles."
  value       = local.operator_role_prefix
}

output "operator_role_arns" {
  description = "Map of operator role ARNs (keyed by namespace/name)."
  value = {
    for idx, role in aws_iam_role.operator_role :
    "${local.operator_roles_properties[idx].operator_namespace}/${local.operator_roles_properties[idx].operator_name}" => role.arn
  }
}

#------------------------------------------------------------------------------
# Ready Signals
#------------------------------------------------------------------------------

output "iam_ready" {
  description = "Indicates IAM resources are ready (after propagation delay)."
  value       = time_sleep.iam_propagation.id
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "iam_summary" {
  description = "Summary of IAM configuration."
  value = {
    account_roles = {
      created   = var.create_account_roles
      prefix    = var.account_role_prefix
      installer = local.installer_role_arn
      support   = local.support_role_arn
      worker    = local.worker_role_arn
    }
    operator_roles = {
      prefix = local.operator_role_prefix
      count  = length(aws_iam_role.operator_role)
      arns = {
        for idx, role in aws_iam_role.operator_role :
        "${local.operator_roles_properties[idx].operator_namespace}/${local.operator_roles_properties[idx].operator_name}" => role.arn
      }
    }
    oidc = {
      config_id    = local.oidc_config_id
      endpoint_url = local.oidc_endpoint_url
      provider_arn = var.create_oidc_config ? aws_iam_openid_connect_provider.this[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
      managed      = var.create_oidc_config ? var.managed_oidc : null
      created      = var.create_oidc_config
    }
  }
}
