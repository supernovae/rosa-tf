#------------------------------------------------------------------------------
# ROSA Classic Commercial - Production Environment (Cluster Only)
#------------------------------------------------------------------------------
# Multi-AZ private cluster with full security and high availability.
#
# Characteristics:
# - Private cluster (most secure, API accessible only from VPC)
# - Multi-AZ for high availability
# - KMS encryption for cluster and infrastructure
# - FIPS optional (enable for regulated workloads)
# - Jump host for secure access
# - VPC flow logs enabled
#
# Two-phase workflow:
#   Phase 1: terraform apply -var-file="cluster-prod.tfvars"
#   Phase 2: terraform apply -var-file="cluster-prod.tfvars" -var-file="gitops-prod.tfvars"
#
# Prerequisites:
#   export TF_VAR_rhcs_client_id="your-client-id"
#   export TF_VAR_rhcs_client_secret="your-client-secret"
#   See: https://console.redhat.com/iam/service-accounts
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "prod-classic" # Change this for your cluster
environment  = "prod"

#------------------------------------------------------------------------------
# Region
#------------------------------------------------------------------------------

aws_region = "us-east-1" # Change to your preferred region

#------------------------------------------------------------------------------
# Topology: Multi-AZ, Private
#------------------------------------------------------------------------------

multi_az = true # 3 AZs, NAT per AZ for HA

# Private cluster (recommended for production - secure by default)
private_cluster = true

# Auto-select 3 AZs
availability_zones = null

#------------------------------------------------------------------------------
# Security / Encryption: Production-grade
#
# Two separate keys for blast radius containment:
# - cluster_kms_*: For ROSA workers and etcd ONLY
# - infra_kms_*: For jump host, CloudWatch, S3/OADP, VPN ONLY
#
# Production RECOMMENDATION: Use customer-managed KMS keys for:
# - Full audit trail of key usage in CloudTrail
# - Custom key rotation policies
# - etcd encryption at rest
# - Compliance requirements (PCI-DSS, HIPAA, etc.)
#------------------------------------------------------------------------------

fips = false # Set to true for FedRAMP/HIPAA/PCI

# KMS encryption (separate keys for cluster and infrastructure)
cluster_kms_mode        = "create" # Customer-managed KMS for ROSA
infra_kms_mode          = "create" # Customer-managed KMS for infrastructure
etcd_encryption         = false    # Encrypt etcd with cluster KMS
kms_key_deletion_window = 30

#------------------------------------------------------------------------------
# Compute: Production sizing
#------------------------------------------------------------------------------

compute_machine_type = "m6i.xlarge"
worker_node_count    = 3 # 1 per AZ minimum
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
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.21.0"
channel_group     = "stable"

#------------------------------------------------------------------------------
# Network
#------------------------------------------------------------------------------

vpc_cidr    = "10.0.0.0/16"
egress_type = "nat"

# Enable flow logs for compliance
enable_vpc_flow_logs     = true
flow_logs_retention_days = 90

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
# oidc_endpoint_url  = "rh-oidc.s3.us-east-1.amazonaws.com/abc123..."

# Unmanaged OIDC (customer-managed, full control)
# create_oidc_config          = true
# managed_oidc                = false
# oidc_private_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:oidc-key"
# installer_role_arn_for_oidc = "arn:aws:iam::123456789:role/Installer-Role"

#------------------------------------------------------------------------------
# Access: Jump host for private cluster
#------------------------------------------------------------------------------

# htpasswd admin user -- required for initial bootstrap (creates OAuth token).
# After bootstrap, Terraform uses the SA token (gitops_cluster_token).
# To harden: set to false and run terraform apply to remove htpasswd IDP.
# See docs/OPERATIONS.md for the full credential lifecycle.
create_admin_user      = true
create_jumphost        = true
jumphost_instance_type = "t3.micro"

# Consider VPN for better UX
create_client_vpn = false # Enable if needed (~$116/month)

#------------------------------------------------------------------------------
# GitOps Configuration
# Set install_gitops = false for Phase 1. Use gitops-prod.tfvars overlay for Phase 2.
#
# ⚠️ TWO-PHASE DEPLOYMENT REQUIRED FOR PRIVATE CLUSTERS:
# This cluster is private - GitOps requires VPN/network connectivity.
# Phase 1: Deploy cluster + VPN with install_gitops = false
# Phase 2: Connect to VPN, then apply gitops-prod.tfvars overlay
# See: docs/OPERATIONS.md "Two-Phase Deployment for Private Clusters"
#------------------------------------------------------------------------------

install_gitops = false

#------------------------------------------------------------------------------
# Optional Features
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Machine Pools (optional - disabled by default)
#
# Generic list - define any pool type by configuration.
# Production pools should use autoscaling for resilience.
# Classic supports spot instances for cost optimization.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# Production examples (uncomment to enable):
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
#   #   instance_type = "g4dn.xlarge"
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
#   # ARM/Graviton Pool - production cost optimization
#   # {
#   #   name          = "graviton"
#   #   instance_type = "m7g.xlarge"
#   #   autoscaling   = { enabled = true, min = 2, max = 10 }
#   #   labels        = { "kubernetes.io/arch" = "arm64" }
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
  Project     = "rosa-commercial"
  CostCenter  = "prod"
}
