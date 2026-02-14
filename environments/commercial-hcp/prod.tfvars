#------------------------------------------------------------------------------
# ROSA HCP - Commercial AWS - Production Environment
#
# Highly available multi-AZ configuration for production workloads.
# Includes encryption, private networking, and VPN access.
#
# Usage:
#   terraform init
#   terraform plan -var-file="prod.tfvars"
#   terraform apply -var-file="prod.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification
#------------------------------------------------------------------------------

cluster_name = "prod-hcp"
environment  = "prod"
aws_region   = "us-east-1"

#------------------------------------------------------------------------------
# OpenShift Version
# Control plane and machine pools use same version by default
# For upgrades: set machine_pool_version to upgrade pools separately
# EUS recommended for production stability
#------------------------------------------------------------------------------

openshift_version = "4.20.10"
# machine_pool_version = "4.20.10"  # Uncomment to upgrade pools separately (must be within n-2 of control plane)
channel_group = "stable"

#------------------------------------------------------------------------------
# Network Configuration
# Multi-AZ for high availability
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = true # 3 AZs, NAT per AZ for HA

#------------------------------------------------------------------------------
# Cluster Configuration
# Private cluster for security
#------------------------------------------------------------------------------

private_cluster      = true
compute_machine_type = "m5.xlarge"
worker_node_count    = 3

#------------------------------------------------------------------------------
# Encryption Configuration
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

cluster_kms_mode = "create" # Customer-managed KMS for ROSA
infra_kms_mode   = "create" # Customer-managed KMS for infrastructure
etcd_encryption  = true     # Encrypt etcd with customer-managed key

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
# External Authentication (HCP Only)
# Replace built-in OpenShift OAuth with external OIDC IdP
#------------------------------------------------------------------------------

external_auth_providers_enabled = false

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

# htpasswd admin user -- required for initial bootstrap (creates OAuth token).
# After bootstrap, Terraform uses the SA token (gitops_cluster_token).
# To harden: set to false and run terraform apply to remove htpasswd IDP.
# See docs/OPERATIONS.md for the full credential lifecycle.
create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# Machine Pools (optional - disabled by default)
#
# Generic list - define any pool type by configuration.
# Production pools should use autoscaling for resilience.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# Production examples (uncomment to enable):
#
# machine_pools = [
#   # General worker pool with autoscaling
#   # {
#   #   name          = "workers"
#   #   instance_type = "m5.xlarge"
#   #   autoscaling   = { enabled = true, min = 2, max = 6 }
#   # },
#   #
#   # GPU Pool - for ML/AI workloads with autoscaling
#   # {
#   #   name          = "gpu"
#   #   instance_type = "g4dn.xlarge"
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
#   # ARM/Graviton Pool - production cost optimization
#   # {
#   #   name          = "graviton"
#   #   instance_type = "m7g.xlarge"
#   #   autoscaling   = { enabled = true, min = 2, max = 10 }
#   #   labels = { "kubernetes.io/arch" = "arm64" }
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
# Jump host and VPN for private cluster access
#------------------------------------------------------------------------------

# Jump host with SSM
create_jumphost        = true
jumphost_instance_type = "t3.small"

# Client VPN
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
# ⚠️ TWO-PHASE DEPLOYMENT REQUIRED FOR PRIVATE CLUSTERS:
# This cluster is private - GitOps requires VPN/network connectivity.
#
# Phase 1: Deploy cluster + VPN with install_gitops = false
# Phase 2: Connect to VPN, then set install_gitops = true and re-apply
#
# See: docs/OPERATIONS.md "Two-Phase Deployment for Private Clusters"
#------------------------------------------------------------------------------

install_gitops           = false # Phase 1: false, Phase 2: true (after VPN connect)
enable_layer_terminal    = false # Web Terminal operator
enable_layer_oadp        = false # Backup/restore (requires S3 bucket)
enable_layer_monitoring  = false # Prometheus + Loki logging stack
enable_layer_certmanager = false # Cert-Manager with Let's Encrypt (see examples/certmanager.tfvars)
# enable_layer_virtualization = false # Requires bare metal nodes

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
monitoring_retention_days = 30 # Prod: 30 days

# Additional GitOps configuration (optional)
# Provide a Git repo URL to deploy custom resources (projects, quotas, RBAC)
# via ArgoCD Application alongside the built-in layers.
# gitops_repo_url = "https://github.com/your-org/my-cluster-config.git"

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
  DataClass      = "confidential"
  BackupRequired = "true"
}
