#------------------------------------------------------------------------------
# ROSA HCP Account Layer - Commercial AWS Configuration
#
# This file configures shared account-level resources for ROSA HCP
# in Commercial AWS (aws partition).
#
# Deploy ONCE per AWS account/region, before creating any HCP clusters.
#
# Usage:
#   terraform plan -var-file="commercial.tfvars"
#   terraform apply -var-file="commercial.tfvars"
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Partition Validation
#------------------------------------------------------------------------------

# IMPORTANT: This value is validated against the actual AWS partition.
# Do not change this - use govcloud.tfvars for GovCloud deployments.
target_partition = "commercial"

#------------------------------------------------------------------------------
# AWS Configuration
#------------------------------------------------------------------------------

aws_region  = "us-east-1"
environment = "account"

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

# Account role prefix - matches ROSA CLI default for interoperability
# This allows using roles created by either Terraform or ROSA CLI
account_role_prefix = "ManagedOpenShift"

# IAM path (optional)
# path = "/"

#------------------------------------------------------------------------------
# KMS Configuration (Optional)
#------------------------------------------------------------------------------

# If using customer-managed KMS keys, add them here:
# kms_key_arns = [
#   "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
# ]

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  "cost-center" = "rosa-platform"
  "team"        = "platform-engineering"
}
