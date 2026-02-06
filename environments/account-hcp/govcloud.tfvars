#------------------------------------------------------------------------------
# ROSA HCP Account Layer - AWS GovCloud Configuration
#
# This file configures shared account-level resources for ROSA HCP
# in AWS GovCloud (aws-us-gov partition).
#
# Deploy ONCE per AWS account/region, before creating any HCP clusters.
#
# Usage:
#   terraform plan -var-file="govcloud.tfvars"
#   terraform apply -var-file="govcloud.tfvars"
#
# GovCloud Requirements:
#   - FIPS mode is mandatory for clusters
#   - Private clusters only (no public endpoints)
#   - Customer-managed KMS keys recommended for FedRAMP compliance
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Partition Validation
#------------------------------------------------------------------------------

# IMPORTANT: This value is validated against the actual AWS partition.
# Do not change this - use commercial.tfvars for Commercial AWS deployments.
target_partition = "govcloud"

#------------------------------------------------------------------------------
# AWS Configuration
#------------------------------------------------------------------------------

aws_region  = "us-gov-west-1"
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
# KMS Configuration (Required for FedRAMP)
#------------------------------------------------------------------------------

# GovCloud/FedRAMP deployments should use customer-managed KMS keys.
# Add your KMS key ARNs here for installer/support role access:
# kms_key_arns = [
#   "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/12345678-1234-1234-1234-123456789012"
# ]

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  "cost-center" = "rosa-platform"
  "team"        = "platform-engineering"
  "Compliance"  = "fedramp-high"
}
