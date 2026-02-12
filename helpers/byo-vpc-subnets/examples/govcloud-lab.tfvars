#------------------------------------------------------------------------------
# BYO-VPC Subnet Helper -- GovCloud Lab Example
#
# Creates subnets for a second ROSA Classic cluster in a GovCloud VPC.
# Uses TGW egress (common in GovCloud) or NAT if standalone.
#
# Prerequisites:
#   1. Deploy first cluster in govcloud-classic (creates VPC)
#   2. Get VPC ID:  cd environments/govcloud-classic && terraform output vpc_id
#
# Usage:
#   cd helpers/byo-vpc-subnets
#   terraform init
#   terraform apply -var-file=examples/govcloud-lab.tfvars
#   # Copy the output subnet IDs into your byovpc-dev.tfvars
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Existing VPC -- CHANGE THESE
#------------------------------------------------------------------------------

vpc_id     = "vpc-CHANGEME" # <-- terraform output vpc_id
aws_region = "us-gov-west-1"

#------------------------------------------------------------------------------
# Second Cluster Identity
#------------------------------------------------------------------------------

cluster_name = "dev-classic-2"

#------------------------------------------------------------------------------
# Subnet Configuration (Single-AZ for dev/test)
#
# The first cluster (default VPC CIDR 10.0.0.0/16) typically uses:
#   Private: 10.0.0.0/20  (us-gov-west-1a)
#   Public:  10.0.48.0/20 (us-gov-west-1a)  -- if NAT mode
#
# For single-AZ dev, we just need one subnet in the next /20 block:
#------------------------------------------------------------------------------

availability_zones = [
  "us-gov-west-1a",
]

private_subnet_cidrs = [
  "10.0.96.0/20", # us-gov-west-1a
]

# Multi-AZ (uncomment for HA):
# availability_zones = [
#   "us-gov-west-1a",
#   "us-gov-west-1b",
#   "us-gov-west-1c",
# ]
#
# private_subnet_cidrs = [
#   "10.0.96.0/20",   # us-gov-west-1a
#   "10.0.112.0/20",  # us-gov-west-1b
#   "10.0.128.0/20",  # us-gov-west-1c
# ]

# GovCloud Classic is always private -- no public subnets needed
# create_public_subnets = false

#------------------------------------------------------------------------------
# Egress -- reuse parent VPC's NAT gateway (default)
# Switch to TGW if your GovCloud VPC uses Transit Gateway for egress
#------------------------------------------------------------------------------

egress_type = "nat"

# For TGW mode (common in GovCloud hub-spoke), uncomment:
# egress_type        = "tgw"
# transit_gateway_id = "tgw-CHANGEME"

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "dev"
  Purpose     = "byo-vpc-second-cluster"
  ManagedBy   = "helpers/byo-vpc-subnets"
}
