#------------------------------------------------------------------------------
# ROSA HCP Account Roles Module
#
# Creates ACCOUNT-LEVEL IAM roles for ROSA HCP that are shared across clusters.
# These roles are created once per AWS account and referenced by all HCP clusters.
#
# Account Roles (3 for HCP):
#   - Installer Role: Used during cluster installation
#   - Support Role: Used by Red Hat SRE for support access  
#   - Worker Role: Used by worker nodes
#
# Unlike ROSA Classic (which uses cluster-scoped roles), ROSA HCP uses
# account-level roles that are shared across multiple clusters.
#
# IMPORTANT:
# - Deploy this module ONCE per AWS account/region
# - All HCP clusters in the account will reference these shared roles
# - Do not destroy while any HCP clusters are using these roles
#
# Naming Convention (matches ROSA CLI):
#   {prefix}-HCP-ROSA-Installer-Role
#   {prefix}-HCP-ROSA-Support-Role
#   {prefix}-HCP-ROSA-Worker-Role
#
# Default prefix is "ManagedOpenShift" (matches ROSA CLI default).
# This allows interoperability with roles created via rosa CLI.
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "rhcs_info" "current" {}
data "rhcs_hcp_policies" "all_policies" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  path       = coalesce(var.path, "/")

  # Determine if KMS permissions should be enabled
  # Use explicit variable if set, otherwise infer from kms_key_arns length
  enable_kms = coalesce(var.enable_kms_permissions, length(var.kms_key_arns) > 0)

  # Account role prefix - default matches ROSA CLI for interoperability
  account_role_prefix = var.account_role_prefix

  # Account roles configuration (matches official RHCS module)
  account_roles_properties = [
    {
      role_name            = "HCP-ROSA-Installer"
      role_type            = "installer"
      policy_arn           = "arn:${local.partition}:iam::aws:policy/service-role/ROSAInstallerPolicy"
      principal_type       = "AWS"
      principal_identifier = "arn:${local.partition}:iam::${data.rhcs_info.current.ocm_aws_account_id}:role/RH-Managed-OpenShift-Installer"
    },
    {
      role_name            = "HCP-ROSA-Support"
      role_type            = "support"
      policy_arn           = "arn:${local.partition}:iam::aws:policy/service-role/ROSASRESupportPolicy"
      principal_type       = "AWS"
      principal_identifier = data.rhcs_hcp_policies.all_policies.account_role_policies["sts_support_rh_sre_role"]
    },
    {
      role_name            = "HCP-ROSA-Worker"
      role_type            = "instance_worker"
      policy_arn           = "arn:${local.partition}:iam::aws:policy/service-role/ROSAWorkerInstancePolicy"
      principal_type       = "Service"
      principal_identifier = "ec2.amazonaws.com"
    },
  ]

  # Role names (for outputs and references)
  installer_role_name = "${local.account_role_prefix}-HCP-ROSA-Installer-Role"
  support_role_name   = "${local.account_role_prefix}-HCP-ROSA-Support-Role"
  worker_role_name    = "${local.account_role_prefix}-HCP-ROSA-Worker-Role"
}

#------------------------------------------------------------------------------
# Account Roles (Shared across HCP clusters)
#------------------------------------------------------------------------------

# Trust policies for account roles
data "aws_iam_policy_document" "account_trust_policy" {
  count = length(local.account_roles_properties)

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = local.account_roles_properties[count.index].principal_type
      identifiers = [local.account_roles_properties[count.index].principal_identifier]
    }
  }
}

# Account roles - shared across all HCP clusters in this account
resource "aws_iam_role" "account_role" {
  count = length(local.account_roles_properties)

  name               = substr("${local.account_role_prefix}-${local.account_roles_properties[count.index].role_name}-Role", 0, 64)
  path               = local.path
  assume_role_policy = data.aws_iam_policy_document.account_trust_policy[count.index].json

  tags = merge(var.tags, {
    red-hat-managed       = true
    rosa_hcp_policies     = true
    rosa_managed_policies = true
    rosa_role_prefix      = local.account_role_prefix
    rosa_role_type        = local.account_roles_properties[count.index].role_type
    rosa_account_layer    = true
  })

  # Lifecycle protection for shared account roles
  #
  # IMPORTANT: These roles are shared by ALL HCP clusters in the account.
  # Deleting them will break all existing clusters!
  #
  # Options for production:
  # 1. Fork this module and set prevent_destroy = true
  # 2. Use terraform state rm to remove roles from state before destroy
  # 3. Import roles into a separate state file managed independently
  #
  # prevent_destroy cannot be dynamic in Terraform, so we default to false
  # to allow module iteration during development. See docs/IAM-LIFECYCLE.md.
  lifecycle {
    prevent_destroy = false
  }
}

# Attach AWS managed policies to account roles
resource "aws_iam_role_policy_attachment" "account_role_policy" {
  count = length(local.account_roles_properties)

  role       = aws_iam_role.account_role[count.index].name
  policy_arn = local.account_roles_properties[count.index].policy_arn
}

# Worker Instance Profile (required for EC2 instances)
resource "aws_iam_instance_profile" "worker" {
  name = "${local.account_role_prefix}-HCP-ROSA-Worker-Role"
  role = aws_iam_role.account_role[2].name # Worker is index 2

  tags = merge(var.tags, {
    rosa_managed_policies = true
    rosa_hcp_policies     = true
    rosa_account_layer    = true
  })
}

#------------------------------------------------------------------------------
# Optional: KMS Permissions for Installer/Support Roles
# Required when using customer-managed KMS keys for etcd encryption
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_policy" {
  count = local.enable_kms ? 1 : 0

  statement {
    sid    = "AllowKMSOperations"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = var.kms_key_arns
  }
}

resource "aws_iam_role_policy" "installer_kms" {
  count = local.enable_kms ? 1 : 0

  name   = "KMSAccess"
  role   = aws_iam_role.account_role[0].id # Installer is index 0
  policy = data.aws_iam_policy_document.kms_policy[0].json
}

resource "aws_iam_role_policy" "support_kms" {
  count = local.enable_kms ? 1 : 0

  name   = "KMSAccess"
  role   = aws_iam_role.account_role[1].id # Support is index 1
  policy = data.aws_iam_policy_document.kms_policy[0].json
}

#------------------------------------------------------------------------------
# Wait for IAM propagation
#------------------------------------------------------------------------------

resource "time_sleep" "iam_propagation" {
  create_duration  = "30s"
  destroy_duration = "10s"

  triggers = {
    account_role_arns = jsonencode([for r in aws_iam_role.account_role : r.arn])
    kms_policy_hash   = local.enable_kms ? sha256(jsonencode(var.kms_key_arns)) : ""
  }

  depends_on = [
    aws_iam_role_policy_attachment.account_role_policy,
    aws_iam_instance_profile.worker,
    aws_iam_role_policy.installer_kms,
    aws_iam_role_policy.support_kms,
  ]
}
