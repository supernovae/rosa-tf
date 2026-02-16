#------------------------------------------------------------------------------
# ROSA Classic - Commercial Production BYO-VPC (Multi-AZ)
#
# Second ROSA Classic cluster deploying into an existing VPC in us-east-1
# with 3 AZs for production high availability.
#
# Prerequisites:
#   1. First cluster deployed (owns the VPC) or existing VPC
#   2. Subnets created via helpers/byo-vpc-subnets or pre-existing
#   3. RHCS service account credentials:
#        export TF_VAR_rhcs_client_id="your-client-id"
#        export TF_VAR_rhcs_client_secret="your-client-secret"
#
# Usage:
#   cd environments/commercial-classic
#   terraform workspace new prod-classic-2
#   terraform apply -var-file=../../examples/byovpc-classic-prod.tfvars
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification - CUSTOMIZE THESE
#------------------------------------------------------------------------------

cluster_name = "prod-classic-2" # <-- Must be unique in your org
environment  = "prod"
aws_region   = "us-east-1"

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.20.10" # <-- CHANGE to your desired version
channel_group     = "stable"

#------------------------------------------------------------------------------
# BYO-VPC Configuration (Multi-AZ Production)
#
# Get these from your first cluster or subnet helper:
#   terraform output vpc_id
#   terraform output private_subnet_ids
#   terraform output public_subnet_ids   (if public cluster)
#------------------------------------------------------------------------------

existing_vpc_id = "vpc-CHANGEME" # <-- terraform output vpc_id

# Multi-AZ: 3 subnets across 3 AZs for HA
existing_private_subnet_ids = [ # <-- CHANGE to your subnet IDs
  "subnet-CHANGEME-1a",         # us-east-1a
  "subnet-CHANGEME-1b",         # us-east-1b
  "subnet-CHANGEME-1c",         # us-east-1c
]

# For public clusters, also provide public subnets (must match AZ count):
# existing_public_subnet_ids = [
#   "subnet-CHANGEME-pub-1a",
#   "subnet-CHANGEME-pub-1b",
#   "subnet-CHANGEME-pub-1c",
# ]

#------------------------------------------------------------------------------
# Network CIDRs -- MUST NOT overlap with first cluster
#
# First cluster defaults:
#   pod_cidr     = 10.128.0.0/14
#   service_cidr = 172.30.0.0/16
#   host_prefix  = 23
#------------------------------------------------------------------------------

pod_cidr     = "10.132.0.0/14" # <-- Non-overlapping with first cluster
service_cidr = "172.31.0.0/16" # <-- Non-overlapping with first cluster
host_prefix  = 23

#------------------------------------------------------------------------------
# Cluster Configuration (Production)
#------------------------------------------------------------------------------

private_cluster      = true  # Private API/ingress for production
fips                 = false # Set true if FedRAMP required
compute_machine_type = "m6i.xlarge"
worker_node_count    = 3 # Minimum 3 for multi-AZ HA (1 per AZ)
worker_disk_size     = 300
multi_az             = true # Ignored in BYO-VPC (inferred from 3 subnets)

#------------------------------------------------------------------------------
# Encryption Configuration
#------------------------------------------------------------------------------

cluster_kms_mode = "create" # Customer-managed for production
infra_kms_mode   = "create"
etcd_encryption  = true # Recommended for production

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

# Each Classic cluster gets its own set of roles (cluster-scoped)
# account_role_prefix defaults to cluster_name

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
# GitOps -- enable after cluster is healthy
#------------------------------------------------------------------------------

install_gitops              = false
enable_layer_terminal       = true
enable_layer_oadp           = false
enable_layer_virtualization = false
enable_layer_monitoring     = false
enable_layer_certmanager    = false

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "prod"
  CostCenter  = "production"
  Layers      = "terminal"
}
