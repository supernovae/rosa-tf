#------------------------------------------------------------------------------
# ROSA HCP - Observability Example
#
# Complete example with dedicated monitoring nodes for the observability stack.
# COPY this file to your environment and customize cluster_name, region, etc.
#
# What's different from dev.tfvars:
#   - Dedicated monitoring machine pool on Graviton (ARM) for cost efficiency
#   - PreferNoSchedule taint biases observability workloads to dedicated nodes
#   - monitoring_node_selector and monitoring_tolerations configured
#   - Loki and Prometheus optimized for dedicated nodes
#
# Usage:
#   cp examples/observability.tfvars environments/commercial-hcp/my-cluster.tfvars
#   cd environments/commercial-hcp
#   # Edit my-cluster.tfvars with your cluster_name, region, etc.
#   terraform apply -var-file="my-cluster.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification - CUSTOMIZE THESE
#------------------------------------------------------------------------------

cluster_name = "my-observability-cluster" # <-- CHANGE THIS
environment  = "dev"
aws_region   = "us-east-1" # <-- CHANGE THIS

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.20.10" # <-- CHANGE to your desired version
channel_group     = "stable"

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = false # Set true for production HA

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

private_cluster      = false # Set true for private clusters
compute_machine_type = "m5.xlarge"
worker_node_count    = 3

#------------------------------------------------------------------------------
# Encryption Configuration
#------------------------------------------------------------------------------

cluster_kms_mode = "provider_managed"
infra_kms_mode   = "provider_managed"

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
# efficiency. Graviton provides ~20-40% better price-performance vs x86
# for workloads like Loki, Prometheus, and Vector that benefit from high
# memory bandwidth and throughput.
#
# c7g.4xlarge: 16 vCPU, 32 GiB RAM (Graviton3, ARM64)
# ~30% cheaper than equivalent c5.4xlarge (x86)
#
# PreferNoSchedule allows monitoring pods to land here preferentially
# while not blocking scheduling if nodes are still initializing.
#------------------------------------------------------------------------------

machine_pools = [
  {
    name          = "monitoring"
    instance_type = "c7g.4xlarge" # Graviton3 ARM - best price-performance for observability
    replicas      = 4             # 4 nodes for HA across Loki, Prometheus, Vector
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

#------------------------------------------------------------------------------
# Monitoring Configuration
#
# Node placement configured to use the dedicated monitoring pool above.
#------------------------------------------------------------------------------

monitoring_loki_size               = "1x.extra-small" # Use 1x.small for production
monitoring_retention_days          = 7                # Use 30 for production
monitoring_prometheus_storage_size = "100Gi"
monitoring_storage_class           = "gp3-csi"

# Node selector matches the label on our monitoring machine pool
monitoring_node_selector = {
  "node-role.kubernetes.io/monitoring" = ""
}

# Tolerations allow Loki pods to schedule on tainted monitoring nodes
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
  Purpose     = "observability-example"
}
