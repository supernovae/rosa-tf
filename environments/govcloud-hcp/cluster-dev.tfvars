#------------------------------------------------------------------------------
# ROSA HCP - AWS GovCloud - Development Environment (Cluster Phase)
#
# Cost-optimized single-AZ configuration for development and testing.
# All GovCloud security requirements are ENFORCED (FIPS, private, KMS).
#
# Estimated monthly cost: ~$600-800 (vs ~$1500+ for prod)
#
# TWO-PHASE WORKFLOW:
#   Phase 1 (cluster only):
#     terraform apply -var-file="cluster-dev.tfvars"
#   Phase 2 (with GitOps, after VPN connected):
#     terraform apply -var-file="cluster-dev.tfvars" -var-file="gitops-dev.tfvars"
#
# Usage:
#   export TF_VAR_ocm_token="your-token-from-console.openshiftusgov.com"
#   terraform init
#   terraform plan -var-file="cluster-dev.tfvars"
#   terraform apply -var-file="cluster-dev.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification
#------------------------------------------------------------------------------

cluster_name = "dev-hcp-gov"
environment  = "dev"
aws_region   = "us-gov-west-1"

#------------------------------------------------------------------------------
# OpenShift Version
# Control plane and machine pools use same version by default
# For upgrades: set machine_pool_version to upgrade pools separately
# EUS recommended for GovCloud stability
#------------------------------------------------------------------------------

openshift_version = "4.16.55"
# machine_pool_version = "4.16.55"  # Uncomment to upgrade pools separately (must be within n-2 of control plane)
channel_group = "eus"

#------------------------------------------------------------------------------
# Network Configuration
# Single-AZ for cost savings (still private, still secure)
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = false # Single AZ, single NAT

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

#------------------------------------------------------------------------------
# Cluster Configuration
# Note: FIPS, private, KMS are MANDATORY - not configurable
#------------------------------------------------------------------------------

compute_machine_type = "m6i.4xlarge"
worker_node_count    = 4

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

create_ecr = true # Set to true to create ECR repository
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
# Machine Pools (Optional)
#
# Generic list - define any pool type by configuration.
# Note: Check GovCloud availability for specific instance types.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# GovCloud examples (uncomment to enable):
#
# machine_pools = [
#   # GPU Pool - for ML/AI workloads (check GovCloud availability)
#   # {
#   #   name          = "gpu"
#   #   instance_type = "p3.2xlarge"  # GovCloud: p3.2xlarge, p3.8xlarge, g4dn.xlarge
#   #   replicas      = 1
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
#   # High Memory Pool - for data-intensive workloads
#   # {
#   #   name          = "highmem"
#   #   instance_type = "r5.2xlarge"
#   #   replicas      = 2
#   #   labels        = { "node-role.kubernetes.io/highmem" = "" }
#   # },
#   #
#   # Bare Metal Pool - for OpenShift Virtualization
#   # {
#   #   name          = "metal"
#   #   instance_type = "m6i.metal"
#   #   replicas      = 2
#   #   labels        = { "node-role.kubernetes.io/metal" = "" }
#   #   taints = [{
#   #     key           = "node-role.kubernetes.io/metal"
#   #     value         = "true"
#   #     schedule_type = "NoSchedule"
#   #   }]
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

# Enable cluster autoscaler (disabled by default for dev - cost control)
# cluster_autoscaler_enabled = true

# Maximum nodes across all autoscaling machine pools
# autoscaler_max_nodes_total = 50

# Example: Enable autoscaling in dev
# cluster_autoscaler_enabled = true
# autoscaler_max_nodes_total = 20
# machine_pools = [
#   {
#     name          = "workers"
#     instance_type = "m6i.xlarge"
#     autoscaling   = { enabled = true, min = 2, max = 10 }
#   }
# ]

#------------------------------------------------------------------------------
# Access Configuration
# Jump host recommended for private cluster access
#------------------------------------------------------------------------------

create_jumphost        = true
jumphost_instance_type = "t3.micro"

# VPN optional for dev
create_client_vpn = true

#------------------------------------------------------------------------------
# GitOps Configuration
# Phase 1: Cluster only. Phase 2: Use gitops-dev.tfvars overlay.
#------------------------------------------------------------------------------

install_gitops = false # Use gitops-dev.tfvars overlay for Phase 2

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true # Show deployment duration in outputs

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "dev"
  CostCenter  = "development"
  Compliance  = "fedramp-high"
  DataClass   = "cui"
}
