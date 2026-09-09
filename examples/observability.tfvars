#------------------------------------------------------------------------------
# ROSA HCP - Observability Example
#
# Complete example with dedicated monitoring nodes for the observability stack.
# COPY this file to your environment and customize cluster_name, region, etc.
#
# What's different from dev.tfvars:
#   - Dedicated monitoring machine pool on Graviton (ARM) for cost efficiency
#   - Node selector places observability workloads; soft taint discourages others
#   - monitoring_node_selector and monitoring_tolerations configured
#   - Loki and Prometheus optimized for dedicated nodes
#
# Usage:
#   cp examples/observability.tfvars environments/commercial-hcp/my-cluster.tfvars
#   cd environments/commercial-hcp
#   # Edit my-cluster.tfvars with your cluster_name, region, etc.
#   terraform apply -var-file="my-cluster.tfvars" -var=install_gitops=false
#   # After the cluster/pool is ready and catalogs/support are verified:
#   terraform apply -var-file="my-cluster.tfvars"
#   # See docs/OBSERVABILITY.md for application onboarding and acceptance.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification - CUSTOMIZE THESE
#------------------------------------------------------------------------------

cluster_name = "my-obs-cluster" # <-- CHANGE THIS (max 15 chars)
environment  = "dev"
aws_region   = "us-east-1" # <-- CHANGE THIS

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

# Set openshift_version explicitly in your private cluster base after regional discovery.
channel_group = "stable"

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = false # Set true for production HA

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

private_cluster      = true # Private connectivity is a prerequisite.
compute_machine_type = "m6i.xlarge"
worker_node_count    = 3

#------------------------------------------------------------------------------
# Encryption Configuration
#------------------------------------------------------------------------------

cluster_kms_mode = "create"
infra_kms_mode   = "create"

#------------------------------------------------------------------------------
# IAM Configuration (HCP requires account roles to exist first)
#------------------------------------------------------------------------------

account_role_prefix = "ManagedOpenShift"

#------------------------------------------------------------------------------
# OIDC Configuration
#------------------------------------------------------------------------------

create_oidc_config = true
managed_oidc       = true

#------------------------------------------------------------------------------
# External Authentication (HCP Only)
#------------------------------------------------------------------------------

external_auth_providers_enabled = false

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# Machine Pools
#
# Dedicated monitoring pool using AWS Graviton (ARM) instances for cost
# efficiency. Compare equal-memory/vCPU regional rates, then benchmark ingestion,
# queries and cardinality. See docs/OBSERVABILITY.md for transparent cost math.
#
# m7g.4xlarge: 16 vCPU, 64 GiB RAM (Graviton3, ARM64).
# Verify ROSA account/region, catalog image architectures and AZ capacity.
#
# PreferNoSchedule softly discourages other workloads; the selector below pins
# Loki and user metrics here. They remain Pending until eligible nodes exist.
# Vector still collects from ALL workers, including the x86 default pool.
#------------------------------------------------------------------------------

machine_pools = [
  {
    name          = "monitoring"
    instance_type = "m7g.4xlarge" # Memory-balanced starting point; measure before production
    replicas      = 3             # Single-AZ demo is NOT AZ-resilient; use multi-AZ in production
    labels = {
      "node-role.kubernetes.io/monitoring" = ""
    }
    taints = [{
      key           = "workload"
      value         = "monitoring"
      schedule_type = "PreferNoSchedule"
    }]
  }
]

#------------------------------------------------------------------------------
# Access Configuration
#------------------------------------------------------------------------------

create_jumphost   = false
create_client_vpn = false

#------------------------------------------------------------------------------
# GitOps Configuration
#------------------------------------------------------------------------------

install_gitops              = true
enable_layer_terminal       = false
enable_layer_oadp           = false
enable_layer_virtualization = false
enable_layer_monitoring     = true # <-- This enables the monitoring layer
enable_layer_certmanager    = false

#------------------------------------------------------------------------------
# Monitoring Configuration
#
# Node placement configured to use the dedicated monitoring pool above.
#------------------------------------------------------------------------------

monitoring_loki_size               = "1x.extra-small" # Use 1x.small for production
monitoring_retention_days          = 7                # Use 30 for production
monitoring_prometheus_storage_size = "100Gi"
monitoring_storage_class           = "gp3-csi"
monitoring_enable_perses           = false # Enable after confirming COO >=1.5 in the catalog

# Node selector matches the label on our monitoring machine pool
monitoring_node_selector = {
  "kubernetes.io/arch"                 = "arm64"
  "node-role.kubernetes.io/monitoring" = ""
}

# Tolerations cover Loki and user Prometheus/Thanos Ruler/Alertmanager.
monitoring_tolerations = [
  {
    key      = "workload"
    operator = "Equal"
    value    = "monitoring"
    effect   = "PreferNoSchedule"
  }
]

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "dev"
  CostCenter  = "development"
  Layers      = "monitoring"
}
