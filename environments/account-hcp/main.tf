#------------------------------------------------------------------------------
# ROSA HCP Account Layer
#
# Creates shared account-level resources for ROSA HCP clusters:
#   - Account IAM roles (Installer, Support, Worker)
#   - Optional: Shared KMS keys, S3 buckets, etc.
#
# DEPLOYMENT:
#   This environment should be deployed ONCE per AWS account/region.
#   All HCP clusters in the account will reference these shared resources.
#
# LIFECYCLE:
#   - Deploy before creating any HCP clusters
#   - Update independently of clusters (e.g., to upgrade role policies)
#   - Do not destroy while any HCP clusters are using these resources
#
# Usage:
#   # For Commercial AWS:
#   terraform apply -var-file="commercial.tfvars"
#
#   # For AWS GovCloud:
#   terraform apply -var-file="govcloud.tfvars"
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Provider Configuration
#------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy       = "terraform"
      ROSAAccountRole = "true"
      Environment     = var.environment
    }
  }
}

provider "rhcs" {
  # Auto-detect GovCloud from AWS partition
  url = local.is_govcloud ? "https://api.openshiftusgov.com" : "https://api.openshift.com"

  # Authentication:
  #   Commercial: use client_id + client_secret (service account)
  #   GovCloud:   use token (offline OCM token)
  token         = var.ocm_token
  client_id     = var.rhcs_client_id
  client_secret = var.rhcs_client_secret
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  is_govcloud = local.partition == "aws-us-gov"

  common_tags = merge(
    var.tags,
    {
      AccountLayer    = "rosa-hcp"
      Partition       = local.partition
      ROSAEnvironment = local.is_govcloud ? "govcloud" : "commercial"
    }
  )
}

#------------------------------------------------------------------------------
# Partition Validation
#
# Ensures the correct tfvars file is used for the target partition.
# Prevents accidentally deploying commercial config to GovCloud or vice versa.
#------------------------------------------------------------------------------

check "partition_validation" {
  assert {
    condition = (
      (var.target_partition == "commercial" && !local.is_govcloud) ||
      (var.target_partition == "govcloud" && local.is_govcloud)
    )
    error_message = <<-EOT
      
      ══════════════════════════════════════════════════════════════════════════════
      PARTITION MISMATCH
      ══════════════════════════════════════════════════════════════════════════════
      
      You are using the wrong tfvars file for this AWS partition.
      
      Current AWS partition: ${local.partition}
      tfvars target:         ${var.target_partition}
      
      ┌──────────────────────────────────────────────────────────────────────────┐
      │ FIX: Use the correct tfvars file                                        │
      └──────────────────────────────────────────────────────────────────────────┘
      
      For Commercial AWS (aws partition):
        terraform apply -var-file="commercial.tfvars"
      
      For AWS GovCloud (aws-us-gov partition):
        terraform apply -var-file="govcloud.tfvars"
      
      ══════════════════════════════════════════════════════════════════════════════
    EOT
  }
}

#------------------------------------------------------------------------------
# HCP Account Roles (Shared)
#------------------------------------------------------------------------------

module "hcp_account_roles" {
  source = "../../modules/account/rosa-hcp-account"

  account_role_prefix = var.account_role_prefix
  path                = var.path
  kms_key_arns        = var.kms_key_arns

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Optional: Shared KMS Keys
# Uncomment if you want account-wide KMS keys for all HCP clusters
#------------------------------------------------------------------------------

# module "shared_kms" {
#   source = "../../modules/security/kms"
#   count  = var.create_shared_kms ? 1 : 0
#
#   cluster_name         = "hcp-shared"
#   account_role_prefix  = var.account_role_prefix
#   operator_role_prefix = var.account_role_prefix
#
#   cluster_kms_mode = "create"
#   infra_kms_mode   = "create"
#
#   tags = local.common_tags
# }
