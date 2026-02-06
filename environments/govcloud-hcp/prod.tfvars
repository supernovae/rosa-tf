#------------------------------------------------------------------------------
# ROSA HCP - AWS GovCloud - Production Environment
#
# Highly available multi-AZ configuration for production FedRAMP workloads.
# All GovCloud security requirements are ENFORCED (FIPS, private, KMS).
#
# Estimated monthly cost: ~$1500-2000+
#
# Usage:
#   export TF_VAR_ocm_token="your-token-from-console.openshiftusgov.com"
#   terraform init
#   terraform plan -var-file="prod.tfvars"
#   terraform apply -var-file="prod.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification
#------------------------------------------------------------------------------

cluster_name = "prod-hcp-gov"
environment  = "prod"
aws_region   = "us-gov-west-1"

#------------------------------------------------------------------------------
# OpenShift Version
# Control plane and machine pools use same version by default
# For upgrades: set machine_pool_version to upgrade pools separately
# EUS mandatory for production
#------------------------------------------------------------------------------

openshift_version = "4.16.54"
# machine_pool_version = "4.16.54"  # Uncomment to upgrade pools separately (must be within n-2 of control plane)
channel_group = "eus"

#------------------------------------------------------------------------------
# Network Configuration
# Multi-AZ for high availability
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = true # 3 AZs, NAT per AZ for HA

#------------------------------------------------------------------------------
# KMS Configuration
# Note: GovCloud requires customer-managed KMS (FedRAMP compliance)
#
# Two separate keys for blast radius containment:
# - cluster_kms_*: For ROSA workers and etcd ONLY
# - infra_kms_*: For jump host, CloudWatch, S3/OADP, VPN ONLY
#
# Options: "create" (default) or "existing"
# "provider_managed" is NOT available in GovCloud
#------------------------------------------------------------------------------

cluster_kms_mode        = "create" # Terraform creates cluster KMS key
infra_kms_mode          = "create" # Terraform creates infrastructure KMS key
kms_key_deletion_window = 30       # Days before keys are permanently deleted

#------------------------------------------------------------------------------
# Cluster Configuration
# Note: FIPS, private, KMS are MANDATORY - not configurable
#------------------------------------------------------------------------------

compute_machine_type = "m5.xlarge"
worker_node_count    = 3

#------------------------------------------------------------------------------
# Zero Egress Configuration (HCP Only)
# Enable for fully air-gapped operation with no outbound internet
#------------------------------------------------------------------------------

# Zero-egress mode (NOT YET AVAILABLE in GovCloud - requires OpenShift 4.18+)
# TODO: Enable when 4.18 ships for GovCloud
zero_egress = false # ⚠️ Must be false until 4.18 is available

#------------------------------------------------------------------------------
# ECR Configuration (Optional)
# Private container registry for custom images or operator mirroring
#------------------------------------------------------------------------------

create_ecr = false # Set to true to create ECR repository
# ecr_repository_name = "custom-name"  # Optional: defaults to {cluster_name}-registry
# ecr_prevent_destroy = true           # Preserve ECR when cluster is destroyed

#------------------------------------------------------------------------------
# IAM Configuration (Account Roles)
#
# PREREQUISITE: HCP account roles must exist BEFORE deploying this cluster.
# See docs/IAM-LIFECYCLE.md for architecture details.
#
# Create account roles via:
#   cd environments/account-hcp && terraform apply -var-file=govcloud.tfvars
# Or:
#   rosa create account-roles --hosted-cp --mode auto
#------------------------------------------------------------------------------

account_role_prefix = "ManagedOpenShift"

#------------------------------------------------------------------------------
# OIDC Configuration
#
# Three modes supported (see docs/OIDC.md for details):
# 1. Managed (default): Red Hat hosts OIDC, created per-cluster
# 2. Pre-created: Use existing managed OIDC config ID
# 3. Unmanaged: Customer hosts OIDC in their AWS account
#------------------------------------------------------------------------------

# Default: create new managed OIDC per-cluster (simplest, recommended)
create_oidc_config = true
managed_oidc       = true

# Pre-created managed OIDC (faster deploys, share across clusters)
# create_oidc_config = false
# oidc_config_id     = "abc123def456..."
# oidc_endpoint_url  = "rh-oidc.s3.us-gov-west-1.amazonaws.com/abc123..."

# Unmanaged OIDC (customer-managed, full control)
# create_oidc_config          = true
# managed_oidc                = false
# oidc_private_key_secret_arn = "arn:aws-us-gov:secretsmanager:us-gov-west-1:123456789:secret:oidc-key"
# installer_role_arn_for_oidc = "arn:aws-us-gov:iam::123456789:role/Installer-Role"

#------------------------------------------------------------------------------
# External Authentication (HCP Only)
# Replace built-in OpenShift OAuth with external OIDC IdP
#------------------------------------------------------------------------------

external_auth_providers_enabled = false

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# Machine Pools (optional - disabled by default)
#
# Generic list - define any pool type by configuration.
# Production pools should use autoscaling for resilience.
# Note: Check GovCloud availability for specific instance types.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# GovCloud production examples (uncomment to enable):
#
# machine_pools = [
#   # General worker pool with autoscaling
#   # {
#   #   name          = "workers"
#   #   instance_type = "m5.xlarge"
#   #   autoscaling   = { enabled = true, min = 2, max = 6 }
#   # },
#   #
#   # GPU Pool - for ML/AI workloads (check GovCloud availability)
#   # {
#   #   name          = "gpu"
#   #   instance_type = "p3.2xlarge"  # GovCloud: p3.2xlarge, p3.8xlarge, g4dn.xlarge
#   #   autoscaling   = { enabled = true, min = 0, max = 4 }
#   #   labels = {
#   #     "node-role.kubernetes.io/gpu"    = ""
#   #     "nvidia.com/gpu.workload.config" = "container"
#   #   }
#   #   taints = [{
#   #     key           = "nvidia.com/gpu"
#   #     value         = "true"
#   #     schedule_type = "NoSchedule"
#   #   }]
#   # },
#   #
#   # Bare Metal Pool - for OpenShift Virtualization
#   # {
#   #   name          = "metal"
#   #   instance_type = "m5.metal"
#   #   replicas      = 3
#   #   labels        = { "node-role.kubernetes.io/metal" = "" }
#   #   taints = [{
#   #     key           = "node-role.kubernetes.io/metal"
#   #     value         = "true"
#   #     schedule_type = "NoSchedule"
#   #   }]
#   # },
#   #
#   # High Memory Pool - data-intensive workloads
#   # {
#   #   name          = "highmem"
#   #   instance_type = "r5.2xlarge"
#   #   autoscaling   = { enabled = true, min = 2, max = 8 }
#   #   labels        = { "node-role.kubernetes.io/highmem" = "" }
#   # },
# ]

#------------------------------------------------------------------------------
# Cluster Autoscaler
#
# The cluster autoscaler controls cluster-wide scaling behavior.
# For HCP, it's fully managed by Red Hat (runs with control plane).
#
# IMPORTANT: Both cluster autoscaler AND machine pool autoscaling must be
# enabled for automatic scaling to work.
#------------------------------------------------------------------------------

# Enable cluster autoscaler for production resilience
cluster_autoscaler_enabled = true

# Maximum nodes across all autoscaling machine pools
autoscaler_max_nodes_total = 100

# Node provision timeout (how long to wait for a node)
# autoscaler_max_node_provision_time = "25m"

# Pod grace period during scale down (seconds)
# autoscaler_max_pod_grace_period = 600

# Example: Production configuration with autoscaling
# machine_pools = [
#   {
#     name          = "workers"
#     instance_type = "m5.xlarge"
#     autoscaling   = { enabled = true, min = 3, max = 20 }
#   }
# ]

#------------------------------------------------------------------------------
# Access Configuration
# Both jump host and VPN recommended for production
#------------------------------------------------------------------------------

# Jump host with SSM (always recommended)
create_jumphost        = true
jumphost_instance_type = "t3.small"

# Client VPN for broader team access
# Note: Certificates are auto-generated - no ACM setup required
# Cost: ~$116/month, takes 15-20 min to create
create_client_vpn = false
# vpn_client_cidr_block     = "10.100.0.0/22"
# vpn_split_tunnel          = true
# vpn_session_timeout_hours = 12

#------------------------------------------------------------------------------
# GitOps Configuration
# Install ArgoCD and optional operators/layers
#
# ⚠️ TWO-PHASE DEPLOYMENT REQUIRED FOR GOVCLOUD:
# All GovCloud clusters are private - GitOps requires VPN connectivity.
#
# Phase 1: Deploy cluster + VPN with install_gitops = false
# Phase 2: Connect to VPN, then set install_gitops = true and re-apply
#
# See: docs/OPERATIONS.md "Two-Phase Deployment for Private Clusters"
#------------------------------------------------------------------------------

install_gitops          = false # Phase 1: false, Phase 2: true (after VPN connect)
enable_layer_terminal   = false # Web Terminal operator
enable_layer_oadp       = false # Backup/restore (requires S3 bucket)
enable_layer_monitoring = false # Prometheus + Loki logging stack
# enable_layer_virtualization = false # Requires bare metal nodes

# Monitoring configuration (when enable_layer_monitoring = true)
monitoring_retention_days = 30 # Prod: 30 days

# Installation method (default: "direct" - applies from local checkout)
# Set to "applicationset" to have ArgoCD pull from your forked Git repo
# layers_install_method = "applicationset"
# gitops_repo_url       = "https://github.com/your-org/rosa-tf.git"

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = false # Set to true to see deployment duration

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment    = "prod"
  CostCenter     = "production"
  Compliance     = "fedramp-high"
  DataClass      = "cui"
  BackupRequired = "true"
  CriticalSystem = "true"
}
