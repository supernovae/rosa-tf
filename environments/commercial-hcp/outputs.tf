#------------------------------------------------------------------------------
# ROSA HCP - Commercial AWS Outputs
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Information
#------------------------------------------------------------------------------

output "cluster_id" {
  description = "ROSA HCP cluster ID."
  value       = module.rosa_cluster.cluster_id
}

output "cluster_name" {
  description = "Cluster name."
  value       = module.rosa_cluster.cluster_name
}

output "cluster_state" {
  description = "Current cluster state."
  value       = module.rosa_cluster.cluster_state
}

output "cluster_api_url" {
  description = "URL of the OpenShift API server."
  value       = module.rosa_cluster.api_url
}

output "cluster_console_url" {
  description = "URL of the OpenShift web console."
  value       = module.rosa_cluster.console_url
}

output "cluster_version" {
  description = "Current OpenShift version running on the cluster."
  value       = module.rosa_cluster.openshift_version
}

#------------------------------------------------------------------------------
# Admin Credentials
#------------------------------------------------------------------------------

output "cluster_admin_username" {
  description = "Cluster admin username."
  value       = module.rosa_cluster.admin_username
}

output "cluster_admin_password" {
  description = "Cluster admin password."
  value       = module.rosa_cluster.admin_password
  sensitive   = true
}

#------------------------------------------------------------------------------
# Network Information
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "availability_zones" {
  description = "Availability zones used."
  value       = local.availability_zones
}

output "egress_type" {
  description = "The egress type configured for this VPC (nat, tgw, proxy, or none)."
  value       = module.vpc.egress_type
}

output "nat_gateway_ips" {
  description = "Elastic IP addresses of NAT gateways (empty if egress_type != 'nat')."
  value       = module.vpc.nat_gateway_ips
}

output "zero_egress" {
  description = "Whether zero-egress mode is enabled."
  value       = var.zero_egress
}

#------------------------------------------------------------------------------
# ECR Information (Optional)
#------------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "ECR repository URL for docker push/pull (empty if create_ecr = false)."
  value       = var.create_ecr ? module.ecr[0].repository_url : ""
}

output "ecr_registry_url" {
  description = "ECR registry URL for docker login (empty if create_ecr = false)."
  value       = var.create_ecr ? module.ecr[0].registry_url : ""
}

#------------------------------------------------------------------------------
# IAM Information
#------------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "OIDC provider ARN."
  value       = module.iam_roles.oidc_provider_arn
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL."
  value       = module.iam_roles.oidc_endpoint_url
}

output "iam_summary" {
  description = "Summary of IAM configuration."
  value       = module.iam_roles.iam_summary
}

#------------------------------------------------------------------------------
# KMS Information (Separate keys for blast radius containment)
#------------------------------------------------------------------------------

output "cluster_kms_mode" {
  description = "Cluster KMS mode: provider_managed, create, or existing."
  value       = var.cluster_kms_mode
}

output "cluster_kms_key_arn" {
  description = "Cluster KMS key ARN for ROSA workers/etcd (null if provider_managed)."
  value       = local.cluster_kms_key_arn
}

output "infra_kms_mode" {
  description = "Infrastructure KMS mode: provider_managed, create, or existing."
  value       = var.infra_kms_mode
}

output "infra_kms_key_arn" {
  description = "Infrastructure KMS key ARN for jump host/CloudWatch/S3/VPN (null if provider_managed)."
  value       = local.infra_kms_key_arn
}

#------------------------------------------------------------------------------
# Access Information
#------------------------------------------------------------------------------

output "jumphost_instance_id" {
  description = "Jump host instance ID (if created)."
  value       = var.create_jumphost ? module.jumphost[0].instance_id : null
}

output "jumphost_ssm_command" {
  description = "SSM command to connect to jump host."
  value       = var.create_jumphost ? "aws ssm start-session --target ${module.jumphost[0].instance_id}" : null
}

output "vpn_endpoint_id" {
  description = "Client VPN endpoint ID (if created)."
  value       = var.create_client_vpn ? module.client_vpn[0].vpn_endpoint_id : null
}

output "vpn_client_config_path" {
  description = "Path to the OpenVPN client configuration file (null if not created)."
  value       = var.create_client_vpn ? module.client_vpn[0].client_config_path : null
}

output "vpn_connection_instructions" {
  description = "Instructions for connecting via VPN (null if not created)."
  value       = var.create_client_vpn ? module.client_vpn[0].connection_instructions : null
}

#------------------------------------------------------------------------------
# Machine Pools
#------------------------------------------------------------------------------

output "machine_pools_summary" {
  description = "Summary of machine pools."
  value       = length(var.machine_pools) > 0 ? module.machine_pools[0].machine_pools : null
}

#------------------------------------------------------------------------------
# Version Information
#------------------------------------------------------------------------------

locals {
  # Calculate actual machine pool version being used
  actual_machine_pool_version = coalesce(var.machine_pool_version, var.openshift_version)

  # Parse versions for comparison
  cp_parts = split(".", var.openshift_version)
  mp_parts = split(".", local.actual_machine_pool_version)

  # Calculate version drift (minor version difference)
  version_drift = tonumber(local.cp_parts[1]) - tonumber(local.mp_parts[1])

  # Determine drift status
  drift_status = local.version_drift == 0 ? "in_sync" : (
    local.version_drift > 0 && local.version_drift <= 2 ? "within_n2" : "out_of_range"
  )
}

output "version_info" {
  description = "Version and upgrade information."
  value = {
    control_plane_version = var.openshift_version
    machine_pool_version  = local.actual_machine_pool_version
    channel_group         = var.channel_group
    version_drift         = local.version_drift
    drift_status          = local.drift_status
    drift_warning         = local.version_drift > 0 ? "Machine pools are ${local.version_drift} minor version(s) behind control plane. Upgrade machine pools when ready." : null
    upgrade_note          = "HCP upgrade workflow: 1) Update openshift_version, 2) Update machine_pool_version. Machine pools must stay within n-2 of control plane."
  }
}

#------------------------------------------------------------------------------
# Cluster Summary
#------------------------------------------------------------------------------

output "cluster_summary" {
  description = "Summary of cluster deployment."
  value = {
    cluster_name      = module.rosa_cluster.cluster_name
    cluster_type      = local.cluster_type
    region            = var.aws_region
    environment       = var.environment
    private           = var.private_cluster
    zero_egress       = var.zero_egress
    multi_az          = var.multi_az
    worker_nodes      = var.worker_node_count
    openshift_version = var.openshift_version
    api_url           = module.rosa_cluster.api_url
    console_url       = module.rosa_cluster.console_url
    managed_policies  = true
    etcd_encrypted    = var.etcd_encryption
    ecr_enabled       = var.create_ecr
  }
}

#------------------------------------------------------------------------------
# Quick Reference Commands
#------------------------------------------------------------------------------

output "quickstart_commands" {
  description = "Quick reference commands for cluster access."
  value       = <<-EOT
    # Login with cluster-admin
    oc login ${module.rosa_cluster.api_url} -u ${module.rosa_cluster.admin_username} -p $(terraform output -raw cluster_admin_password)
    
    # Open console
    open ${module.rosa_cluster.console_url}
    
    ${var.create_jumphost ? "# Connect via SSM\naws ssm start-session --target ${module.jumphost[0].instance_id}" : "# Jump host not created"}
    
    ${var.create_client_vpn ? "# Download VPN config\naws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id ${module.client_vpn[0].vpn_endpoint_id} --output text > vpn-config.ovpn" : "# VPN not created"}
    
    # Upgrade notes (HCP)
    # Machine pools must be within n-2 of control plane version
    # Upgrade sequence: control plane first, then machine pools
  EOT
}

#------------------------------------------------------------------------------
# GitOps Status
#------------------------------------------------------------------------------

output "cluster_auth_summary" {
  description = <<-EOT
    Cluster authentication status for GitOps installation.
    If authenticated=false, GitOps was skipped. Check 'error' field for details.
  EOT
  value = var.install_gitops && length(module.cluster_auth) > 0 ? module.cluster_auth[0].auth_summary : {
    enabled       = false
    authenticated = false
    host          = ""
    username      = ""
    error         = "install_gitops is false"
  }
}

output "gitops_installed" {
  description = "Whether GitOps was installed."
  value       = var.install_gitops && length(module.gitops) > 0
}

output "gitops_status" {
  description = "GitOps installation status and next steps if not installed."
  value = var.install_gitops ? (
    length(module.gitops) > 0 ? {
      status  = "installed"
      message = "GitOps operator installed successfully"
      } : {
      status  = "skipped"
      message = "GitOps skipped - check cluster_auth_summary"
    }
    ) : {
    status  = "disabled"
    message = "Set install_gitops = true to enable"
  }
}

#------------------------------------------------------------------------------
# Deployment Timing (when enable_timing = true)
#------------------------------------------------------------------------------

output "deployment_timing" {
  description = "Deployment timing summary (only populated when enable_timing = true)."
  value       = var.enable_timing ? module.timing.timing_summary : null
}

#------------------------------------------------------------------------------
# S3 Bucket Cleanup Notice
#------------------------------------------------------------------------------

output "s3_buckets_requiring_manual_cleanup" {
  description = <<-EOT
    S3 buckets that require manual cleanup after terraform destroy.
    
    IMPORTANT: These buckets are NOT automatically deleted to prevent
    accidental data loss. After destroying the cluster, manually delete
    if you no longer need the data:
    
      aws s3 rb s3://BUCKET_NAME --force
  EOT
  value       = var.install_gitops && length(module.gitops_resources) > 0 ? module.gitops_resources[0].s3_buckets_requiring_manual_cleanup : []
}
