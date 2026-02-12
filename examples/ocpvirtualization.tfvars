#------------------------------------------------------------------------------
# ROSA HCP - OpenShift Virtualization Example
#
# Complete example with bare metal nodes for OpenShift Virtualization.
# COPY this file to your environment and customize cluster_name, region, etc.
#
# What's different from dev.tfvars:
#   - Bare metal machine pool (m5.metal) with taints
#   - virt_node_selector and virt_tolerations configured
#   - enable_layer_virtualization = true
#
# Note: m5.metal instances are expensive (~$4.60/hour each)
#
# Usage:
#   cp examples/ocpvirtualization.tfvars environments/commercial-hcp/my-cluster.tfvars
#   cd environments/commercial-hcp
#   # Edit my-cluster.tfvars with your cluster_name, region, etc.
#   terraform apply -var-file="my-cluster.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification - CUSTOMIZE THESE
#------------------------------------------------------------------------------

cluster_name = "my-virt-cluster" # <-- CHANGE THIS
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
# This is the key difference - a bare metal pool for virtualization.
# PreferNoSchedule: non-virt workloads avoid these nodes but VMs can
# schedule without explicit tolerations. Use NoSchedule for strict isolation
# (requires adding tolerations to every VM spec).
#------------------------------------------------------------------------------

machine_pools = [
  {
    name          = "virt"
    instance_type = "m5.metal" # Bare metal required for hardware virtualization
    replicas      = 2          # Minimum 2 for live migration
    labels = {
      "node-role.kubernetes.io/virtualization" = ""
    }
    taints = [{
      key           = "virtualization"
      value         = "true"
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
enable_layer_virtualization = true # <-- This enables the virtualization layer
enable_layer_monitoring     = false
enable_layer_certmanager    = false

#------------------------------------------------------------------------------
# Virtualization Configuration
#
# Node placement configured to use the bare metal pool above.
# The HyperConverged CR will use these to schedule virt components and VMs.
#------------------------------------------------------------------------------

# Node selector matches the label on our bare metal machine pool
virt_node_selector = {
  "node-role.kubernetes.io/virtualization" = ""
}

# Tolerations allow virt infrastructure pods to schedule on tainted bare metal nodes
virt_tolerations = [
  {
    key      = "virtualization"
    operator = "Equal"
    value    = "true"
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
  Layers      = "virtualization"
}
