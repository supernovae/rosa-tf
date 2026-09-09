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


output "api_url" {
  description = "API server URL."
  value = try(
    length(data.rhcs_cluster_rosa_hcp.info.api_url) > 0 ? data.rhcs_cluster_rosa_hcp.info.api_url : null,
    length(rhcs_cluster_rosa_hcp.this.api_url) > 0 ? rhcs_cluster_rosa_hcp.this.api_url : null,
    ""
  )
}

output "console_url" {
  description = "OpenShift console URL."
  value = try(
    length(data.rhcs_cluster_rosa_hcp.info.console_url) > 0 ? data.rhcs_cluster_rosa_hcp.info.console_url : null,
    length(rhcs_cluster_rosa_hcp.this.console_url) > 0 ? rhcs_cluster_rosa_hcp.this.console_url : null,
    ""
  )
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


#------------------------------------------------------------------------------
# Admin Credentials
#------------------------------------------------------------------------------

output "admin_username" {
  description = "Cluster admin username."
  value       = var.create_admin_user ? try(coalesce(rhcs_cluster_rosa_hcp.this.admin_credentials.username, var.admin_username), var.admin_username) : null
  # With two-phase deployment, OAuth has settled by the time Phase 2 runs.
  # No sleep needed -- the time gap between phases handles reconciliation.
  depends_on = [time_sleep.cluster_ready]
}

output "admin_password" {
  description = "Cluster admin password."
  value       = var.create_admin_user ? try(coalesce(rhcs_cluster_rosa_hcp.this.admin_credentials.password, random_password.cluster_admin[0].result), random_password.cluster_admin[0].result) : null
  sensitive   = true
  depends_on  = [time_sleep.cluster_ready]
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
    min_machine_pool_version = "4.${tonumber(split(".", rhcs_cluster_rosa_hcp.this.current_version)[1]) - 2}.0"
    channel_group            = var.channel_group
    version_drift_note       = "Machine pools must be within n-2 of control plane version"
  }
}

#------------------------------------------------------------------------------
# Cluster Autoscaler
#------------------------------------------------------------------------------



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
    cluster_id        = rhcs_cluster_rosa_hcp.this.id
    cluster_name      = rhcs_cluster_rosa_hcp.this.name
    openshift_version = rhcs_cluster_rosa_hcp.this.current_version
    api_url = try(
      length(data.rhcs_cluster_rosa_hcp.info.api_url) > 0 ? data.rhcs_cluster_rosa_hcp.info.api_url : null,
      length(rhcs_cluster_rosa_hcp.this.api_url) > 0 ? rhcs_cluster_rosa_hcp.this.api_url : null,
      ""
    )
    console_url = try(
      length(data.rhcs_cluster_rosa_hcp.info.console_url) > 0 ? data.rhcs_cluster_rosa_hcp.info.console_url : null,
      length(rhcs_cluster_rosa_hcp.this.console_url) > 0 ? rhcs_cluster_rosa_hcp.this.console_url : null,
      ""
    )
    private                         = rhcs_cluster_rosa_hcp.this.private
    zero_egress                     = var.zero_egress
    external_auth_providers_enabled = var.external_auth_providers_enabled
    worker_replicas                 = var.replicas
    etcd_encrypted                  = var.etcd_encryption
    type                            = "hcp"
  }
}
