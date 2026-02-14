#------------------------------------------------------------------------------
# ROSA HCP - Commercial AWS - Development Environment
#
# Cost-optimized single-AZ configuration for development and testing.
# Estimated monthly cost: ~$500-700 (vs ~$1500+ for prod)
#
# Usage:
#   terraform init
#   terraform plan -var-file="dev.tfvars"
#   terraform apply -var-file="dev.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification
#------------------------------------------------------------------------------

cluster_name = "dev-hcp"
environment  = "dev"
aws_region   = "us-east-1"

#------------------------------------------------------------------------------
# OpenShift Version
# Control plane and machine pools use same version by default
# For upgrades: set machine_pool_version to upgrade pools separately
#------------------------------------------------------------------------------

openshift_version = "4.20.10"
# machine_pool_version = "4.20.10"  # Uncomment to upgrade pools separately (must be within n-2 of control plane)
channel_group = "stable"

#------------------------------------------------------------------------------
# Network Configuration
# Single-AZ for cost savings
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = false # Single AZ, single NAT

#------------------------------------------------------------------------------
# Cluster Configuration
# Public cluster for easy development access
#------------------------------------------------------------------------------

private_cluster      = false
compute_machine_type = "m5.xlarge"
worker_node_count    = 2

#------------------------------------------------------------------------------
# Encryption Configuration
#
# Two separate keys for blast radius containment:
# - cluster_kms_*: For ROSA workers and etcd ONLY
# - infra_kms_*: For jump host, CloudWatch, S3/OADP, VPN ONLY
#
# Mode options (same for both keys):
#   "provider_managed" (DEFAULT) - Uses AWS managed aws/ebs key
#     - Encryption at rest enabled by default
#     - No KMS key costs (~$1/month per key)
#     - Simplest configuration
#
#   "create" - Terraform creates customer-managed KMS key
#     - Full control over key policies
#     - Enables etcd encryption option
#     - Required for strict compliance
#
#   "existing" - Use your own KMS key ARN
#     - Set cluster_kms_key_arn or infra_kms_key_arn
#------------------------------------------------------------------------------

cluster_kms_mode = "provider_managed" # Use AWS default for ROSA
infra_kms_mode   = "provider_managed" # Use AWS default for infrastructure

# etcd_encryption only applies when cluster_kms_mode = "create" or "existing"
etcd_encryption = false

#------------------------------------------------------------------------------
# Zero Egress Configuration (HCP Only)
# Enable for fully air-gapped operation with no outbound internet
#------------------------------------------------------------------------------

zero_egress = false # Set to true for air-gapped environments

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
#   cd environments/account-hcp && terraform apply -var-file=commercial.tfvars
# Or:
#   rosa create account-roles --hosted-cp --mode auto
#------------------------------------------------------------------------------

account_role_prefix = "ManagedOpenShift"

# For explicit ARNs (optional, overrides auto-discovery):
# installer_role_arn = "arn:aws:iam::123456789012:role/ManagedOpenShift-HCP-ROSA-Installer-Role"
# support_role_arn   = "arn:aws:iam::123456789012:role/ManagedOpenShift-HCP-ROSA-Support-Role"
# worker_role_arn    = "arn:aws:iam::123456789012:role/ManagedOpenShift-HCP-ROSA-Worker-Role"

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
# oidc_config_id     = "abc123def456..."  # From: rosa list oidc-config
# oidc_endpoint_url  = "rh-oidc.s3.us-east-1.amazonaws.com/abc123..."

# Unmanaged OIDC (customer-managed, full control)
# create_oidc_config          = true
# managed_oidc                = false
# oidc_private_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:oidc-key"
# installer_role_arn_for_oidc = "arn:aws:iam::123456789:role/Installer-Role"

#------------------------------------------------------------------------------
# External Authentication (HCP Only)
#
# Replace built-in OpenShift OAuth with external OIDC IdP (Entra ID, Keycloak)
# IMPORTANT: Cannot be changed after cluster creation!
#------------------------------------------------------------------------------

external_auth_providers_enabled = false

# When enabling external auth:
# - Set create_admin_user = false (OAuth server is replaced)
# - Configure external provider via rosa CLI after cluster creation
# - See docs/OIDC.md for setup guide

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# Machine Pools (Optional)
#
# Generic list - define any pool type by configuration.
# Uncomment and customize examples as needed.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# Example configurations (uncomment to enable):
#
# machine_pools = [
#   # GPU Pool (NVIDIA) - for ML/AI workloads
#   # {
#   #   name          = "gpu"
#   #   instance_type = "g4dn.xlarge"  # or p3.2xlarge, p4d.24xlarge
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
#   # ARM/Graviton Pool - cost optimization (up to 40% savings)
#   # {
#   #   name          = "graviton"
#   #   instance_type = "m6g.xlarge"  # or m7g.xlarge for Graviton3
#   #   autoscaling   = { enabled = true, min = 1, max = 5 }
#   #   labels = {
#   #     "kubernetes.io/arch" = "arm64"
#   #   }
#   # },
#   #
#   # Bare Metal Pool - for OpenShift Virtualization (when enable_layer_virtualization = true)
#   # {
#   #   name          = "metal"
#   #   instance_type = "m5.metal"  # or c5.metal, m5zn.metal
#   #   replicas      = 2
#   #   labels = {
#   #     "node-role.kubernetes.io/metal" = ""
#   #   }
#   #   taints = [{
#   #     key           = "node-role.kubernetes.io/metal"
#   #     value         = "true"
#   #     schedule_type = "NoSchedule"
#   #   }]
#   # },
#   #
#   # High Memory Pool - for memory-intensive workloads
#   # {
#   #   name          = "highmem"
#   #   instance_type = "r5.2xlarge"  # or x2idn.xlarge
#   #   replicas      = 2
#   #   labels = {
#   #     "node-role.kubernetes.io/highmem" = ""
#   #   }
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
#     instance_type = "m5.xlarge"
#     autoscaling   = { enabled = true, min = 2, max = 10 }
#   }
# ]

#------------------------------------------------------------------------------
# Access Configuration
# No VPN or jump host needed for public cluster
#------------------------------------------------------------------------------

create_jumphost   = false
create_client_vpn = false

#------------------------------------------------------------------------------
# GitOps Configuration
# Install ArgoCD and optional operators/layers
#------------------------------------------------------------------------------

install_gitops              = false # Set to true after cluster is ready (Stage 2)
enable_layer_terminal       = false # Web Terminal operator
enable_layer_oadp           = false # Backup/restore (requires S3 bucket)
enable_layer_virtualization = false # Requires bare metal nodes
enable_layer_monitoring     = false # Prometheus + Loki logging stack
enable_layer_certmanager    = false # Cert-Manager with Let's Encrypt (see examples/certmanager.tfvars)

# Cert-Manager configuration (when enable_layer_certmanager = true)
# certmanager_create_hosted_zone        = true
# certmanager_hosted_zone_domain        = "apps.example.com"
# certmanager_acme_email                = "platform-team@example.com"
# certmanager_enable_dnssec             = true
# certmanager_enable_query_logging      = true
# certmanager_enable_routes_integration = true
# certmanager_certificate_domains = [
#   {
#     name        = "apps-wildcard"
#     namespace   = "openshift-ingress"
#     secret_name = "custom-apps-default-cert"
#     domains     = ["*.apps.example.com"]
#   }
# ]
# # Or use an existing hosted zone:
# # certmanager_hosted_zone_id     = "Z0123456789ABCDEF"
# # certmanager_create_hosted_zone = false

# Monitoring configuration (when enable_layer_monitoring = true)
monitoring_loki_size      = "1x.extra-small" # Dev: extra-small, Prod: 1x.small or larger
monitoring_retention_days = 7                # Dev: 7 days, Prod: 30 days
# monitoring_prometheus_storage_size = "50Gi"  # Default: 100Gi

# NOTE: S3 buckets (Loki logs, OADP backups) are NOT deleted on terraform destroy
# to prevent accidental data loss. After destroying the cluster, manually delete
# buckets via: aws s3 rb s3://BUCKET_NAME --force

# Additional GitOps configuration (optional)
# Provide a Git repo URL to deploy custom resources (projects, quotas, RBAC)
# via ArgoCD Application alongside the built-in layers.
# gitops_repo_url = "https://github.com/your-org/my-cluster-config.git"

# Override OAuth URL if auto-detection fails
# gitops_oauth_url = "https://oauth-openshift.apps.<cluster>.<domain>"

# Or provide your own token for external auth
# gitops_cluster_token = "<your-token-here>"

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
}

