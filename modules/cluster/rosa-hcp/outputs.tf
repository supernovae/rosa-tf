#------------------------------------------------------------------------------
# ROSA HCP Cluster Module Outputs
#------------------------------------------------------------------------------

output "cluster_id" {
  description = "ID of the ROSA HCP cluster."
  value       = rhcs_cluster_rosa_hcp.this.id
}

output "cluster_name" {
  description = "Name of the cluster."
  value       = rhcs_cluster_rosa_hcp.this.name
}

output "state" {
  description = "Current state of the cluster."
  value       = rhcs_cluster_rosa_hcp.this.state
}

# Alias for backward compatibility
output "cluster_state" {
  description = "Current state of the cluster (alias for state)."
  value       = rhcs_cluster_rosa_hcp.this.state
}

output "api_url" {
  description = "API server URL."
  value       = rhcs_cluster_rosa_hcp.this.api_url
}

output "console_url" {
  description = "OpenShift console URL."
  value       = rhcs_cluster_rosa_hcp.this.console_url
}

output "domain" {
  description = "Cluster domain name."
  value       = rhcs_cluster_rosa_hcp.this.domain
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL for the cluster."
  value       = rhcs_cluster_rosa_hcp.this.sts.oidc_endpoint_url
}

# Note: HCP clusters don't expose infra_id - the control plane is in Red Hat's account

output "current_version" {
  description = "Deployed OpenShift version."
  value       = rhcs_cluster_rosa_hcp.this.current_version
}

# Alias for backward compatibility
output "openshift_version" {
  description = "Deployed OpenShift version (alias for current_version)."
  value       = rhcs_cluster_rosa_hcp.this.current_version
}

#------------------------------------------------------------------------------
# Admin Credentials
#------------------------------------------------------------------------------

output "admin_username" {
  description = "Cluster admin username."
  value       = var.create_admin_user ? var.admin_username : null
  # Ensure htpasswd IDP is configured and OAuth server has reconciled
  depends_on = [time_sleep.htpasswd_ready]
}

output "admin_password" {
  description = "Cluster admin password."
  value       = var.create_admin_user ? random_password.cluster_admin[0].result : null
  sensitive   = true
  # Ensure htpasswd IDP is configured and OAuth server has reconciled
  depends_on = [time_sleep.htpasswd_ready]
}

# Aliases for backward compatibility
output "cluster_admin_username" {
  description = "Cluster admin username (alias for admin_username)."
  value       = var.create_admin_user ? var.admin_username : null
  depends_on  = [time_sleep.htpasswd_ready]
}

output "cluster_admin_password" {
  description = "Cluster admin password (alias for admin_password)."
  value       = var.create_admin_user ? random_password.cluster_admin[0].result : null
  sensitive   = true
  depends_on  = [time_sleep.htpasswd_ready]
}

#------------------------------------------------------------------------------
# Network Information
#------------------------------------------------------------------------------

output "private" {
  description = "Whether the cluster is private."
  value       = rhcs_cluster_rosa_hcp.this.private
}

output "zero_egress" {
  description = "Whether zero-egress mode is enabled."
  value       = var.zero_egress
}

#------------------------------------------------------------------------------
# External Authentication
#------------------------------------------------------------------------------

output "external_auth_providers_enabled" {
  description = "Whether external OIDC authentication is enabled (HCP only)."
  value       = var.external_auth_providers_enabled
}

#------------------------------------------------------------------------------
# Version Drift Information
#------------------------------------------------------------------------------

output "version_info" {
  description = "Version information for upgrade planning."
  value = {
    control_plane_version    = var.openshift_version
    min_machine_pool_version = "${local.control_plane_major}.${local.min_machine_pool_minor}.0"
    channel_group            = var.channel_group
    version_drift_note       = "Machine pools must be within n-2 of control plane version"
  }
}

#------------------------------------------------------------------------------
# Cluster Autoscaler
#------------------------------------------------------------------------------

output "cluster_autoscaler_enabled" {
  description = "Whether cluster autoscaler is enabled."
  value       = var.cluster_autoscaler_enabled
}

output "cluster_autoscaler_config" {
  description = "Cluster autoscaler configuration (null if not enabled)."
  value = var.cluster_autoscaler_enabled ? {
    max_nodes_total         = var.autoscaler_max_nodes_total
    max_node_provision_time = var.autoscaler_max_node_provision_time
    max_pod_grace_period    = var.autoscaler_max_pod_grace_period
    pod_priority_threshold  = var.autoscaler_pod_priority_threshold
  } : null
}

#------------------------------------------------------------------------------
# Additional Security Groups
#------------------------------------------------------------------------------

output "additional_compute_security_group_ids" {
  description = "Additional security group IDs attached to compute/worker nodes."
  value       = var.aws_additional_compute_security_group_ids
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "cluster_summary" {
  description = "Summary of cluster configuration."
  value = {
    cluster_id                      = rhcs_cluster_rosa_hcp.this.id
    cluster_name                    = rhcs_cluster_rosa_hcp.this.name
    openshift_version               = rhcs_cluster_rosa_hcp.this.current_version
    api_url                         = rhcs_cluster_rosa_hcp.this.api_url
    console_url                     = rhcs_cluster_rosa_hcp.this.console_url
    private                         = rhcs_cluster_rosa_hcp.this.private
    zero_egress                     = var.zero_egress
    external_auth_providers_enabled = var.external_auth_providers_enabled
    worker_replicas                 = var.replicas
    etcd_encrypted                  = var.etcd_encryption
    cluster_autoscaler_enabled      = var.cluster_autoscaler_enabled
    type                            = "hcp"
  }
}
