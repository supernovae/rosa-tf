#------------------------------------------------------------------------------
# BYO-VPC Subnet Helper -- Commercial Production (us-east-1, 3-AZ, NAT)
#
# Creates multi-AZ subnets for a second ROSA Classic cluster in us-east-1.
# Reuses the parent VPC's existing NAT gateway for egress.
#
# Prerequisites:
#   1. Deploy first cluster in commercial-classic (creates VPC)
#   2. Get VPC ID:  cd environments/commercial-classic && terraform output vpc_id
#
# Usage:
#   cd helpers/byo-vpc-subnets
#   terraform init
#   terraform apply -var-file=examples/commercial-prod.tfvars
#   # Copy the output subnet IDs into your cluster tfvars
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Existing VPC -- CHANGE THESE
#------------------------------------------------------------------------------

vpc_id     = "vpc-CHANGEME" # <-- terraform output vpc_id
aws_region = "us-east-1"

#------------------------------------------------------------------------------
# Second Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "prod-classic-2"

#------------------------------------------------------------------------------
# Subnet Configuration (Multi-AZ Production)
#
# First cluster (default VPC CIDR 10.0.0.0/16) typically uses:
#   Private: 10.0.0.0/20 (1a), 10.0.16.0/20 (1b), 10.0.32.0/20 (1c)
#   Public:  10.0.48.0/20 (1a), 10.0.64.0/20 (1b), 10.0.80.0/20 (1c)
#
# We allocate the next available /20 blocks for the second cluster:
#------------------------------------------------------------------------------

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c",
]

private_subnet_cidrs = [
  "10.0.96.0/20",  # us-east-1a
  "10.0.112.0/20", # us-east-1b
  "10.0.128.0/20", # us-east-1c
]

# Uncomment for public clusters:
# create_public_subnets = true
# public_subnet_cidrs = [
#   "10.0.144.0/20",  # us-east-1a
#   "10.0.160.0/20",  # us-east-1b
#   "10.0.176.0/20",  # us-east-1c
# ]

#------------------------------------------------------------------------------
# Egress -- reuse parent VPC's NAT gateway
#------------------------------------------------------------------------------

egress_type = "nat"

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "prod"
  Purpose     = "byo-vpc-second-cluster"
  ManagedBy   = "helpers/byo-vpc-subnets"
}
