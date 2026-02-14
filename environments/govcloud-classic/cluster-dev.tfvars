#------------------------------------------------------------------------------
# ROSA Classic GovCloud - Development Environment (Cluster Phase)
#------------------------------------------------------------------------------
# Single-AZ deployment optimized for cost and development workflows.
#
# Security posture is IDENTICAL to production:
# - FIPS enabled
# - KMS encryption for EBS and etcd
# - Private cluster (no public API endpoint)
# - STS mode
#
# Cost savings vs production:
# - Single AZ (~$64/month NAT savings)
# - Fewer worker nodes
# - Smaller instance types (optional)
#
# TWO-PHASE WORKFLOW:
#   Phase 1 (cluster only):
#     terraform apply -var-file="cluster-dev.tfvars"
#   Phase 2 (with GitOps, after VPN connected):
#     terraform apply -var-file="cluster-dev.tfvars" -var-file="gitops-dev.tfvars"
#
# Usage:
#   cd environments/govcloud-classic
#   terraform plan -var-file="cluster-dev.tfvars"
#   terraform apply -var-file="cluster-dev.tfvars"
#
# Prerequisites:
#   export TF_VAR_ocm_token="your-token-from-console.openshiftusgov.com"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "dev-classic-gov" # Change this for your cluster
environment  = "dev"

#------------------------------------------------------------------------------
# Topology: Single-AZ for Development
#------------------------------------------------------------------------------

multi_az = false # Single AZ, single NAT

# Auto-select first available AZ (or specify one)
availability_zones = null
# availability_zones = ["us-gov-west-1a"]

#------------------------------------------------------------------------------
# Compute: Smaller footprint for dev
#------------------------------------------------------------------------------

compute_machine_type = "m5.xlarge" # Or m5.large for smaller dev
worker_node_count    = 2           # Minimum for single-AZ
worker_disk_size     = 150

#------------------------------------------------------------------------------
# Cluster Autoscaler (Optional)
# Configures cluster-wide autoscaling behavior
#
# IMPORTANT: autoscaler_max_nodes_total MUST be >= worker_node_count
# The autoscaler cannot allow fewer nodes than currently deployed.
#
# For Classic:
#   - max_nodes_total = max worker nodes (NOT control plane or infra)
#   - Set higher than worker_node_count to allow scale-up headroom
#------------------------------------------------------------------------------

cluster_autoscaler_enabled = false # Set to true to enable autoscaling

# Autoscaler settings (when cluster_autoscaler_enabled = true):
# autoscaler_max_nodes_total                  = 10    # Must be >= worker_node_count (2)
# autoscaler_scale_down_enabled               = true  # Enable scale down of idle nodes
# autoscaler_scale_down_utilization_threshold = "0.5" # Scale down if < 50% utilized
# autoscaler_scale_down_delay_after_add       = "10m" # Wait before considering new nodes
# autoscaler_scale_down_unneeded_time         = "10m" # How long node must be idle

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

# Disable flow logs for dev (cost savings)
enable_vpc_flow_logs = false

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

cluster_kms_mode = "create" # Terraform creates cluster KMS key
infra_kms_mode   = "create" # Terraform creates infrastructure KMS key
etcd_encryption  = true     # Always recommended for GovCloud

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
#------------------------------------------------------------------------------

create_admin_user = true
create_jumphost   = true

# VPN optional for dev (SSM is sufficient)
create_client_vpn = false

#------------------------------------------------------------------------------
# GitOps Configuration
# Phase 1: Cluster only. Phase 2: Use gitops-dev.tfvars overlay.
#------------------------------------------------------------------------------

install_gitops = false # Use gitops-dev.tfvars overlay for Phase 2

#------------------------------------------------------------------------------
# Machine Pools (Optional)
#
# Generic list - define any pool type by configuration.
# Classic supports spot instances for cost optimization.
# Note: Check GovCloud availability for specific instance types.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# GovCloud examples (uncomment to enable):
#
# machine_pools = [
#   # GPU Spot Pool - cost-effective ML/batch (up to 90% savings)
#   # {
#   #   name          = "gpu-spot"
#   #   instance_type = "p3.2xlarge"  # GovCloud: p3.2xlarge, p3.8xlarge, g4dn.xlarge
#   #   spot          = { enabled = true }
#   #   autoscaling   = { enabled = true, min = 0, max = 3 }
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
#   #   instance_type = "m5.metal"
#   #   replicas      = 2
#   #   labels        = { "node-role.kubernetes.io/metal" = "" }
#   #   taints        = [{ key = "node-role.kubernetes.io/metal", value = "true", schedule_type = "NoSchedule" }]
#   # },
#   #
#   # High Memory Pool - data-intensive workloads
#   # {
#   #   name          = "highmem"
#   #   instance_type = "r5.2xlarge"
#   #   replicas      = 2
#   #   labels        = { "node-role.kubernetes.io/highmem" = "" }
#   # },
# ]

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true # Show deployment duration in outputs

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "development"
  Project     = "rosa-govcloud"
  CostCenter  = "dev"
}
