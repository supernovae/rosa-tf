#------------------------------------------------------------------------------
# ROSA Cluster Module Outputs
#------------------------------------------------------------------------------

output "cluster_id" {
  description = "The unique identifier of the cluster."
  value       = rhcs_cluster_rosa_classic.this.id
}

output "api_url" {
  description = "URL of the OpenShift API server."
  value       = rhcs_cluster_rosa_classic.this.api_url
}

output "console_url" {
  description = "URL of the OpenShift web console."
  value       = rhcs_cluster_rosa_classic.this.console_url
}

output "domain" {
  description = "DNS domain of the cluster."
  value       = rhcs_cluster_rosa_classic.this.domain
}

output "infra_id" {
  description = "Infrastructure ID of the cluster."
  value       = rhcs_cluster_rosa_classic.this.infra_id
}

output "state" {
  description = "Current state of the cluster."
  value       = rhcs_cluster_rosa_classic.this.state
}

output "current_version" {
  description = "Current OpenShift version."
  value       = rhcs_cluster_rosa_classic.this.current_version
}

output "oidc_config_id" {
  description = "OIDC configuration ID."
  value       = var.oidc_config_id
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL."
  value       = rhcs_cluster_rosa_classic.this.sts.oidc_endpoint_url
}

output "admin_username" {
  description = "Cluster admin username."
  value       = var.create_admin_user ? var.admin_username : null
  # With two-phase deployment, OAuth has settled by the time Phase 2 runs.
  depends_on = [rhcs_group_membership.cluster_admin]
}

output "admin_password" {
  description = "Cluster admin password."
  value       = var.create_admin_user ? random_password.admin[0].result : null
  sensitive   = true
  depends_on  = [rhcs_group_membership.cluster_admin]
}

output "ccs_enabled" {
  description = "Whether CCS is enabled."
  value       = rhcs_cluster_rosa_classic.this.ccs_enabled
}

output "private" {
  description = "Whether the cluster is private."
  value       = rhcs_cluster_rosa_classic.this.private
}

output "fips" {
  description = "Whether FIPS is enabled."
  value       = rhcs_cluster_rosa_classic.this.fips
}

output "multi_az" {
  description = "Whether multi-AZ is enabled."
  value       = rhcs_cluster_rosa_classic.this.multi_az
}

output "aws_account_id" {
  description = "AWS account ID where cluster is deployed."
  value       = rhcs_cluster_rosa_classic.this.aws_account_id
}

# This output depends on the destroy wait time, ensuring proper ordering
output "cluster_destroyed_safely" {
  description = "Indicates the cluster destruction wait has completed."
  value       = true
  depends_on  = [time_sleep.cluster_destroy_wait]
}

#------------------------------------------------------------------------------
# Cluster Autoscaler
#------------------------------------------------------------------------------

output "cluster_autoscaler_enabled" {
  description = "Whether the cluster autoscaler is enabled."
  value       = var.cluster_autoscaler_enabled
}

output "cluster_autoscaler_config" {
  description = "Cluster autoscaler configuration (null if not enabled)."
  value = var.cluster_autoscaler_enabled ? {
    max_nodes_total       = var.autoscaler_max_nodes_total
    scale_down_enabled    = var.autoscaler_scale_down_enabled
    utilization_threshold = var.autoscaler_scale_down_utilization_threshold
  } : null
}

#------------------------------------------------------------------------------
# Additional Security Groups
#------------------------------------------------------------------------------

output "additional_compute_security_group_ids" {
  description = "Additional security group IDs attached to compute/worker nodes."
  value       = var.aws_additional_compute_security_group_ids
}

output "additional_control_plane_security_group_ids" {
  description = "Additional security group IDs attached to control plane nodes."
  value       = var.aws_additional_control_plane_security_group_ids
}

output "additional_infra_security_group_ids" {
  description = "Additional security group IDs attached to infrastructure nodes."
  value       = var.aws_additional_infra_security_group_ids
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "cluster_summary" {
  description = "Summary of cluster configuration."
  value = {
    cluster_id               = rhcs_cluster_rosa_classic.this.id
    cluster_name             = var.cluster_name
    openshift_version        = rhcs_cluster_rosa_classic.this.current_version
    api_url                  = rhcs_cluster_rosa_classic.this.api_url
    console_url              = rhcs_cluster_rosa_classic.this.console_url
    private                  = rhcs_cluster_rosa_classic.this.private
    fips                     = rhcs_cluster_rosa_classic.this.fips
    multi_az                 = rhcs_cluster_rosa_classic.this.multi_az
    worker_count             = var.worker_node_count
    etcd_encrypted           = var.etcd_encryption
    cluster_autoscaler       = var.cluster_autoscaler_enabled
    default_pool_autoscaling = var.autoscaling_enabled
    type                     = "classic"
  }
}
