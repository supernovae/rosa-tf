#------------------------------------------------------------------------------
# ROSA Classic Commercial - Development Environment
#------------------------------------------------------------------------------
# Single-AZ public cluster optimized for cost and development workflows.
#
# Characteristics:
# - Public cluster (direct API/console access from internet)
# - Single AZ (no HA, lower cost)
# - No KMS encryption (AWS-managed encryption still active)
# - No jump host or VPN needed (public access)
# - FIPS disabled (unless required)
#
# Usage:
#   cd environments/commercial-classic
#   terraform plan -var-file=dev.tfvars
#   terraform apply -var-file=dev.tfvars
#
# Prerequisites:
#   export TF_VAR_rhcs_client_id="your-client-id"
#   export TF_VAR_rhcs_client_secret="your-client-secret"
#   See: https://console.redhat.com/iam/service-accounts
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "dev-classic" # Change this for your cluster
environment  = "dev"

#------------------------------------------------------------------------------
# Region
#------------------------------------------------------------------------------

aws_region = "us-east-1" # Change to your preferred region

#------------------------------------------------------------------------------
# Topology: Single-AZ, Public
#------------------------------------------------------------------------------

multi_az = false # Single AZ, single NAT

# Public cluster (simplest for dev - easier testing without jump host/VPN)
private_cluster = false

# Auto-select first available AZ
availability_zones = null

#------------------------------------------------------------------------------
# Security / Encryption: Minimal for Dev
#
# Two separate keys for blast radius containment:
# - cluster_kms_*: For ROSA workers and etcd ONLY
# - infra_kms_*: For jump host, CloudWatch, S3/OADP, VPN ONLY
#
# Mode options (same for both keys):
#   "provider_managed" (DEFAULT) - Uses AWS managed aws/ebs key, no KMS costs
#   "create" - Terraform creates customer-managed KMS key
#   "existing" - Use your own KMS key ARN
#------------------------------------------------------------------------------

fips             = false              # FIPS not needed for dev
cluster_kms_mode = "provider_managed" # Use AWS default for ROSA
infra_kms_mode   = "provider_managed" # Use AWS default for infrastructure
etcd_encryption  = false              # Only applies with custom cluster KMS

#------------------------------------------------------------------------------
# Compute: Smaller footprint
#------------------------------------------------------------------------------

compute_machine_type = "m5.xlarge"
worker_node_count    = 2 # Minimum for single-AZ
worker_disk_size     = 300

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

cluster_autoscaler_enabled = false # Set to true for autoscaling

# Autoscaler settings (when cluster_autoscaler_enabled = true):
# autoscaler_max_nodes_total                  = 10    # Must be >= worker_node_count (2)
# autoscaler_scale_down_enabled               = true  # Enable scale down of idle nodes
# autoscaler_scale_down_utilization_threshold = "0.5" # Scale down if < 50% utilized
# autoscaler_scale_down_delay_after_add       = "10m" # Wait before considering new nodes
# autoscaler_scale_down_unneeded_time         = "10m" # How long node must be idle

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.20.10"
channel_group     = "stable"

#------------------------------------------------------------------------------
# Network
#------------------------------------------------------------------------------

vpc_cidr    = "10.0.0.0/16"
egress_type = "nat"

# Disable flow logs for dev
enable_vpc_flow_logs = false

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
#
# Note: External authentication (external OIDC IdP for users) is HCP-only.
# Classic uses built-in OAuth server with configurable identity providers.
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
# Access: Public cluster needs no jump host
#------------------------------------------------------------------------------

create_admin_user = true
create_jumphost   = false # Not needed for public cluster
create_client_vpn = false # Not needed for public cluster

#------------------------------------------------------------------------------
# GitOps Configuration
# Install ArgoCD and optional operators/layers
#------------------------------------------------------------------------------

install_gitops           = false # Set to true after cluster is ready (Stage 2)
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
monitoring_retention_days = 7 # Dev: 7 days, Prod: 30 days

# Additional GitOps configuration (optional)
# Provide a Git repo URL to deploy custom resources (projects, quotas, RBAC)
# via ArgoCD ApplicationSet alongside the built-in layers.
# gitops_repo_url = "https://github.com/your-org/my-cluster-config.git"

#------------------------------------------------------------------------------
# Optional Features
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Machine Pools (Optional)
#
# Generic list - define any pool type by configuration.
# Classic supports spot instances for cost optimization.
# See docs/MACHINE-POOLS.md for detailed guidance.
#------------------------------------------------------------------------------

machine_pools = []

# Example configurations (uncomment to enable):
#
# machine_pools = [
#   # GPU Spot Pool - cost-effective ML/batch workloads (up to 90% savings)
#   # {
#   #   name          = "gpu-spot"
#   #   instance_type = "g4dn.xlarge"
#   #   spot          = { enabled = true, max_price = "0.50" }
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
#   # GPU Pool (on-demand) - for critical GPU workloads
#   # {
#   #   name          = "gpu"
#   #   instance_type = "g4dn.xlarge"
#   #   replicas      = 1
#   #   labels        = { "node-role.kubernetes.io/gpu" = "" }
#   #   taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
#   # },
#   #
#   # ARM/Graviton Pool - cost optimization (up to 40% savings)
#   # {
#   #   name          = "graviton"
#   #   instance_type = "m6g.xlarge"
#   #   autoscaling   = { enabled = true, min = 1, max = 5 }
#   #   labels        = { "kubernetes.io/arch" = "arm64" }
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
  Project     = "rosa-commercial"
  CostCenter  = "dev"
}
