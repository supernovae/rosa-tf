#------------------------------------------------------------------------------
# BYO-VPC Subnet Helper -- Lab Example
#
# Creates subnets for a second ROSA HCP cluster in the VPC created by the
# first cluster. Uses non-overlapping CIDRs to avoid conflicts.
#
# Prerequisites:
#   1. Deploy first cluster with default settings (creates VPC)
#   2. Get VPC ID:  cd environments/commercial-hcp && terraform output vpc_id
#
# Usage:
#   cd helpers/byo-vpc-subnets
#   terraform init
#   terraform apply -var-file=examples/lab.tfvars
#   # Copy the output subnet IDs into your cluster-2 tfvars
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Existing VPC -- CHANGE THESE
#------------------------------------------------------------------------------

vpc_id     = "vpc-0123456789abcdef0" # <-- terraform output vpc_id
aws_region = "us-east-1"             # <-- Must match VPC region

#------------------------------------------------------------------------------
# Second Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "my-cluster-2"

#------------------------------------------------------------------------------
# Subnet Configuration (Multi-AZ)
#
# The first cluster (default VPC CIDR 10.0.0.0/16) typically uses:
#   Private: 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
#   Public:  10.0.48.0/20, 10.0.64.0/20, 10.0.80.0/20
#
# We allocate the next available /20 blocks:
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
# Egress -- reuse parent VPC's NAT gateway (default)
#------------------------------------------------------------------------------

egress_type = "nat"

# For TGW mode (GovCloud), uncomment:
# egress_type        = "tgw"
# transit_gateway_id = "tgw-0123456789abcdef0"

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "lab"
  Purpose     = "byo-vpc-second-cluster"
  ManagedBy   = "helpers/byo-vpc-subnets"
}
