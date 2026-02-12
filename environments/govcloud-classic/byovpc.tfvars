#------------------------------------------------------------------------------
# ROSA HCP - BYO-VPC Example (Multi-Cluster in Single VPC)
#
# Deploys a second ROSA HCP cluster into an existing VPC created by the
# first cluster (or any pre-existing VPC). This avoids creating duplicate
# VPCs and allows workload isolation within a shared network.
#
# IMPORTANT: Multi-cluster in a single VPC is a supported pattern but an
# anti-pattern. VPC is a good blast radius boundary. See docs/BYO-VPC.md.
#
# Prerequisites:
#   - First cluster deployed with default settings (creates the VPC)
#   - Copy VPC ID and subnet IDs from first cluster's outputs:
#       terraform output vpc_id
#       terraform output private_subnet_ids
#       terraform output public_subnet_ids
#
# CIDR Planning (avoid conflicts with first cluster defaults):
#   First cluster defaults:  pod=10.128.0.0/14, service=172.30.0.0/16
#   Second cluster (below):  pod=10.132.0.0/14, service=172.31.0.0/16
#
# Usage:
#   cp examples/byovpc.tfvars environments/commercial-hcp/my-cluster-2.tfvars
#   cd environments/commercial-hcp
#   # Edit with your values (VPC ID, subnet IDs, cluster name, etc.)
#   terraform apply -var-file="my-cluster-2.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification - CUSTOMIZE THESE
#------------------------------------------------------------------------------

cluster_name = "my-cluster-2" # <-- CHANGE THIS (must be unique per VPC)
environment  = "dev"
aws_region   = "us-east-1" # <-- Must match the existing VPC's region

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.20.10" # <-- CHANGE to your desired version
channel_group     = "stable"

#------------------------------------------------------------------------------
# BYO-VPC Configuration
#
# Provide the VPC and subnet IDs from the first cluster or pre-existing VPC.
# The number of private subnets determines cluster topology:
#   - 1 subnet  = single-AZ cluster (dev/test)
#   - 3 subnets = multi-AZ cluster (production HA)
#------------------------------------------------------------------------------

existing_vpc_id = "vpc-0123456789abcdef0" # <-- CHANGE: from `terraform output vpc_id`

# Multi-AZ example (3 subnets = HA):
existing_private_subnet_ids = [ # <-- CHANGE: from `terraform output private_subnet_ids`
  "subnet-0aaaaaaaaaaaa0001",
  "subnet-0aaaaaaaaaaaa0002",
  "subnet-0aaaaaaaaaaaa0003",
]

# For public clusters, also provide public subnets (must match AZ count):
# existing_public_subnet_ids = [
#   "subnet-0bbbbbbbbbbbb0001",
#   "subnet-0bbbbbbbbbbbb0002",
#   "subnet-0bbbbbbbbbbbb0003",
# ]

# Single-AZ example (uncomment instead of multi-AZ above):
# existing_private_subnet_ids = ["subnet-0aaaaaaaaaaaa0001"]
# existing_public_subnet_ids  = ["subnet-0bbbbbbbbbbbb0001"]

#------------------------------------------------------------------------------
# Network CIDRs (CRITICAL for multi-cluster -- must NOT overlap)
#
# Each cluster needs unique pod and service CIDRs.
# Defaults for first cluster: pod=10.128.0.0/14, service=172.30.0.0/16
#
# Common multi-cluster CIDR plans:
#   Cluster 1: pod=10.128.0.0/14, service=172.30.0.0/16 (defaults)
#   Cluster 2: pod=10.132.0.0/14, service=172.31.0.0/16
#   Cluster 3: pod=10.136.0.0/14, service=172.28.0.0/16
#------------------------------------------------------------------------------

# vpc_cidr is NOT used in BYO-VPC mode (VPC already exists)
pod_cidr     = "10.132.0.0/14" # <-- Non-overlapping with first cluster
service_cidr = "172.31.0.0/16" # <-- Non-overlapping with first cluster
host_prefix  = 23

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

private_cluster      = true # Typically matches first cluster's config
compute_machine_type = "m5.xlarge"
worker_node_count    = 2 # Smaller for dev/test second cluster

#------------------------------------------------------------------------------
# Encryption Configuration
#------------------------------------------------------------------------------

cluster_kms_mode = "provider_managed"
infra_kms_mode   = "provider_managed"

#------------------------------------------------------------------------------
# IAM Configuration
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
# Access Configuration
#------------------------------------------------------------------------------

create_jumphost   = false # First cluster's jumphost can access both clusters
create_client_vpn = false # First cluster's VPN covers the shared VPC

#------------------------------------------------------------------------------
# GitOps Configuration
#------------------------------------------------------------------------------

install_gitops              = true
enable_layer_terminal       = true
enable_layer_oadp           = false
enable_layer_virtualization = false
enable_layer_monitoring     = false

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "dev"
  Purpose     = "byo-vpc-second-cluster"
}
