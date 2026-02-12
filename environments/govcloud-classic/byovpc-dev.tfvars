#------------------------------------------------------------------------------
# ROSA Classic - GovCloud BYO-VPC Dev/Test
#
# Second cluster deploying into an existing VPC.
# NOT checked in -- personal lab use only.
#
# Prerequisites:
#   - First cluster deployed (owns the VPC)
#   - VPC ID + subnet IDs from first cluster's outputs
#   - OCM token: export TF_VAR_ocm_token="your-token"
#
# Usage:
#   cd environments/govcloud-classic
#   terraform workspace new cluster-2
#   terraform apply -var-file=byovpc-dev.tfvars
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification
#------------------------------------------------------------------------------

cluster_name = "dev-classic-2" # <-- Must be unique in your org
environment  = "dev"
aws_region   = "us-gov-west-1"

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.16.50"
channel_group     = "eus"

#------------------------------------------------------------------------------
# BYO-VPC Configuration
#
# Get these from your first cluster:
#   terraform output vpc_id
#   terraform output private_subnet_ids
#------------------------------------------------------------------------------

existing_vpc_id = "vpc-0267d2227cf4a3317" # <-- terraform output vpc_id

# Single-AZ for dev/test (1 subnet):
existing_private_subnet_ids = [
  "subnet-011e50e01cdc73b76", # <-- one private subnet from first cluster or helper
]

# Multi-AZ for HA (3 subnets) -- uncomment instead of above:
# existing_private_subnet_ids = [
#   "subnet-CHANGEME-1",
#   "subnet-CHANGEME-2",
#   "subnet-CHANGEME-3",
# ]

# GovCloud Classic is always private -- no public subnets needed
# existing_public_subnet_ids = []

#------------------------------------------------------------------------------
# Network CIDRs -- MUST NOT overlap with first cluster
#
# First cluster defaults:
#   pod_cidr     = 10.128.0.0/14
#   service_cidr = 172.30.0.0/16
#------------------------------------------------------------------------------

vpc_cidr     = "10.0.0.0/16"   # Only used if NOT using BYO-VPC (ignored here)
pod_cidr     = "10.132.0.0/14" # <-- Non-overlapping with first cluster
service_cidr = "172.31.0.0/16" # <-- Non-overlapping with first cluster
host_prefix  = 23

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

compute_machine_type = "m5.xlarge"
worker_node_count    = 2 # Smaller for dev second cluster
worker_disk_size     = 300
multi_az             = false # Ignored in BYO-VPC (inferred from subnets)

#------------------------------------------------------------------------------
# Encryption (FedRAMP -- customer-managed KMS required)
#------------------------------------------------------------------------------

cluster_kms_mode = "create"
infra_kms_mode   = "create"

#------------------------------------------------------------------------------
# OIDC Configuration
#------------------------------------------------------------------------------

create_oidc_config = true
managed_oidc       = true

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# Access Configuration
#------------------------------------------------------------------------------

create_jumphost   = false # First cluster's jumphost covers the VPC
create_client_vpn = false # First cluster's VPN covers the VPC

#------------------------------------------------------------------------------
# GitOps -- disabled for initial deploy, enable after cluster is up
#------------------------------------------------------------------------------

install_gitops              = false
enable_layer_terminal       = false
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
