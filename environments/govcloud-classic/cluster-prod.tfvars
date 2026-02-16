#------------------------------------------------------------------------------
# ROSA Classic GovCloud - Production Environment (Cluster Phase)
#------------------------------------------------------------------------------
# Multi-AZ deployment with full high availability.
#
# Production characteristics:
# - 3 availability zones for HA
# - 3 NAT gateways (survives AZ failure)
# - Minimum 3 worker nodes (1 per AZ)
# - VPC flow logs enabled for compliance
# - All security features enabled (FIPS, KMS, private cluster, STS)
#
# ⚠️ TWO-PHASE DEPLOYMENT REQUIRED FOR GOVCLOUD:
# All GovCloud clusters are private - GitOps requires VPN connectivity.
# Phase 1: Deploy cluster (and VPN if needed). Phase 2: Connect VPN, apply gitops overlay.
#
# TWO-PHASE WORKFLOW:
#   Phase 1 (cluster only):
#     terraform apply -var-file="cluster-prod.tfvars"
#   Phase 2 (with GitOps, after VPN connected):
#     terraform apply -var-file="cluster-prod.tfvars" -var-file="gitops-prod.tfvars"
#
# Usage:
#   cd environments/govcloud-classic
#   terraform plan -var-file="cluster-prod.tfvars"
#   terraform apply -var-file="cluster-prod.tfvars"
#
# Prerequisites:
#   export TF_VAR_ocm_token="your-token-from-console.openshiftusgov.com"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "prod-classic-gov" # Change this for your cluster
environment  = "prod"

#------------------------------------------------------------------------------
# Topology: Multi-AZ for Production
#------------------------------------------------------------------------------

multi_az = true # 3 AZs, NAT per AZ for HA

# Auto-select 3 AZs (or specify explicitly)
availability_zones = null
# availability_zones = ["us-gov-west-1a", "us-gov-west-1b", "us-gov-west-1c"]

#------------------------------------------------------------------------------
# Compute: Production sizing
#------------------------------------------------------------------------------

compute_machine_type = "m6i.xlarge"
worker_node_count    = 3 # 1 per AZ minimum, scale as needed
worker_disk_size     = 300

#------------------------------------------------------------------------------
# Cluster Autoscaler (Optional)
# Configures cluster-wide autoscaling behavior for production workloads
#
# IMPORTANT: autoscaler_max_nodes_total MUST be >= worker_node_count
# The autoscaler cannot allow fewer nodes than currently deployed.
#
# For Classic:
#   - max_nodes_total = max worker nodes (NOT control plane or infra)
#   - Set higher than worker_node_count to allow scale-up headroom
#------------------------------------------------------------------------------

cluster_autoscaler_enabled = false # Set to true for production autoscaling

# Production autoscaler settings (when cluster_autoscaler_enabled = true):
# autoscaler_max_nodes_total                  = 50    # Must be >= worker_node_count (3)
# autoscaler_scale_down_enabled               = true  # Enable scale down during off-peak
# autoscaler_scale_down_utilization_threshold = "0.5" # Scale down if < 50% utilized
# autoscaler_scale_down_delay_after_add       = "10m" # Stabilization period after scale up
# autoscaler_scale_down_unneeded_time         = "10m" # Grace period before scale down

#------------------------------------------------------------------------------
# Region and Version
#------------------------------------------------------------------------------

aws_region        = "us-gov-west-1"
openshift_version = "4.16.50"
channel_group     = "eus"

#------------------------------------------------------------------------------
# Network
#------------------------------------------------------------------------------

vpc_cidr    = "10.0.0.0/16"
egress_type = "nat"

# Enable flow logs for compliance/audit
enable_vpc_flow_logs     = true
flow_logs_retention_days = 90

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
etcd_encryption         = true     # Always recommended for GovCloud

#------------------------------------------------------------------------------
# ECR Configuration (Optional)
# Private container registry for custom images
#------------------------------------------------------------------------------

create_ecr = false # Set to true to create ECR repository
# ecr_repository_name = "custom-name"  # Optional: defaults to {cluster_name}-registry
# ecr_prevent_destroy = true           # Preserve ECR when cluster is destroyed

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
# Access
#
# htpasswd admin user -- required for initial bootstrap (creates OAuth token).
# After bootstrap, Terraform uses the SA token (gitops_cluster_token).
# To harden: set to false and run terraform apply to remove htpasswd IDP.
# See docs/OPERATIONS.md for the full credential lifecycle.
#------------------------------------------------------------------------------

create_admin_user = true
create_jumphost   = true

# Consider VPN for production (better UX than SSM)
create_client_vpn = false # Enable if budget allows (~$116/month)

#------------------------------------------------------------------------------
# GitOps Configuration
# Phase 1: Cluster only. Phase 2: Use gitops-prod.tfvars overlay.
#------------------------------------------------------------------------------

install_gitops = false # Use gitops-prod.tfvars overlay for Phase 2

#------------------------------------------------------------------------------
# Machine Pools (optional - disabled by default)
#
# Generic list - define any pool type by configuration.
# Production pools should use autoscaling for resilience.
# Classic supports spot instances for cost optimization.
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
#   #   instance_type = "m6i.xlarge"
#   #   autoscaling   = { enabled = true, min = 2, max = 6 }
#   # },
#   #
#   # GPU Spot Pool - cost-effective ML/batch (up to 90% savings)
#   # {
#   #   name          = "gpu-spot"
#   #   instance_type = "p3.2xlarge"  # GovCloud: p3.2xlarge, p3.8xlarge, g4dn.xlarge
#   #   spot          = { enabled = true }
#   #   autoscaling   = { enabled = true, min = 0, max = 4 }
#   #   multi_az      = false
#   #   labels = {
#   #     "node-role.kubernetes.io/gpu" = ""
#   #     "spot"                        = "true"
#   #   }
#   #   taints = [
#   #     { key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" },
#   #     { key = "spot", value = "true", schedule_type = "PreferNoSchedule" }
#   #   ]
#   # },
#   #
#   # Bare Metal Pool - for OpenShift Virtualization
#   # {
#   #   name          = "metal"
#   #   instance_type = "m6i.metal"
#   #   replicas      = 3
#   #   labels        = { "node-role.kubernetes.io/metal" = "" }
#   #   taints        = [{ key = "node-role.kubernetes.io/metal", value = "true", schedule_type = "NoSchedule" }]
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
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = false # Set to true to see deployment duration

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "production"
  Project     = "rosa-govcloud"
  CostCenter  = "prod"
  Compliance  = "fedramp-high"
}
