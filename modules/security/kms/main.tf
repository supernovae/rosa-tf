#------------------------------------------------------------------------------
# KMS Module for ROSA Clusters
#
# Creates two SEPARATE KMS keys with STRICT SEPARATION:
#
# 1. CLUSTER KMS KEY (cluster_kms_mode)
#    - Purpose: ROSA-managed resources ONLY
#    - Usage: Worker EBS volumes, etcd encryption
#    - Policy: Red Hat expected permissions (account roles, operator roles)
#    - DO NOT use for non-ROSA resources
#
# 2. INFRASTRUCTURE KMS KEY (infra_kms_mode)
#    - Purpose: Non-ROSA resources ONLY
#    - Usage: Jump host, CloudWatch, S3/OADP, VPN logs
#    - Policy: AWS services (logs, s3) + root account
#    - DO NOT attach to ROSA workers (prevents blast radius crossover)
#
# Each key supports three modes:
#   - "provider_managed": Returns null, uses AWS managed aws/ebs key
#   - "create": Terraform creates customer-managed key with proper policy
#   - "existing": Uses customer-provided key ARN
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------

locals {
  # Should we create each key?
  create_cluster_key = var.cluster_kms_mode == "create"
  create_infra_key   = var.infra_kms_mode == "create"

  # Determine the KMS key ARNs to output
  cluster_kms_key_arn = (
    var.cluster_kms_mode == "provider_managed" ? null :
    var.cluster_kms_mode == "create" ? aws_kms_key.cluster[0].arn :
    var.cluster_kms_key_arn
  )

  infra_kms_key_arn = (
    var.infra_kms_mode == "provider_managed" ? null :
    var.infra_kms_mode == "create" ? aws_kms_key.infrastructure[0].arn :
    var.infra_kms_key_arn
  )
}

#==============================================================================
# CLUSTER KMS KEY
# For ROSA-managed resources: worker EBS, etcd encryption
# Policy follows Red Hat's expected permissions - DO NOT MODIFY without
# verifying against Red Hat documentation
#==============================================================================

resource "aws_kms_key" "cluster" {
  count = local.create_cluster_key ? 1 : 0

  description              = "ROSA cluster KMS key for ${var.cluster_name} - workers and etcd"
  deletion_window_in_days  = var.kms_key_deletion_window
  enable_key_rotation      = true
  is_enabled               = true
  multi_region             = false
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage                = "ENCRYPT_DECRYPT"

  policy = data.aws_iam_policy_document.cluster_kms_policy[0].json

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-cluster-kms"
      Purpose = "rosa-cluster-encryption"
      Scope   = "rosa-workers-etcd"
    }
  )
}

resource "aws_kms_alias" "cluster" {
  count = local.create_cluster_key ? 1 : 0

  name          = "alias/${var.cluster_name}-cluster"
  target_key_id = aws_kms_key.cluster[0].key_id
}

#------------------------------------------------------------------------------
# Cluster KMS Key Policy
# IMPORTANT: This policy follows Red Hat's expected permissions for ROSA.
# Changes here may break cluster functionality.
#
# SECURITY NOTE (Checkov CKV_AWS_109, CKV_AWS_111, CKV_AWS_356):
# These policies use resources = ["*"] which is REQUIRED for KMS key policies:
# - KMS key policies are resource-based policies attached TO a specific key
# - Within a key policy, "*" means "this key only" - it cannot reference other keys
# - You cannot reference a key's ARN during creation (circular dependency)
# - This is AWS recommended practice
#
# checkov:skip=CKV_AWS_109:KMS key policy resources="*" refers to this key only
# checkov:skip=CKV_AWS_111:KMS key policy resources="*" refers to this key only
# checkov:skip=CKV_AWS_356:KMS key policy resources="*" refers to this key only
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_kms_policy" {
  count = local.create_cluster_key ? 1 : 0

  #--------------------------------------------------------------------------
  # Root Account Access (Required for key administration)
  #--------------------------------------------------------------------------

  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  #--------------------------------------------------------------------------
  # ROSA Account Roles (Installer, Support, Worker)
  #--------------------------------------------------------------------------

  statement {
    sid    = "AllowROSAAccountRoles"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.account_role_prefix}-*-Role",
      ]
    }
  }

  statement {
    sid    = "AllowROSAAccountRolesToCreateGrants"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.account_role_prefix}-*-Role",
      ]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  #--------------------------------------------------------------------------
  # ROSA Operator Roles (CSI Driver, Machine API, etc.)
  #--------------------------------------------------------------------------

  statement {
    sid    = "AllowROSAOperatorRoles"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.operator_role_prefix}-openshift-*",
      ]
    }
  }

  statement {
    sid    = "AllowROSAOperatorRolesToCreateGrants"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.operator_role_prefix}-openshift-*",
      ]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  #--------------------------------------------------------------------------
  # HCP Worker Node EBS Encryption (EC2/Auto Scaling Service Principals)
  # Required for all HCP clusters - CAPA uses these services to create workers
  #--------------------------------------------------------------------------

  dynamic "statement" {
    for_each = var.is_hcp_cluster ? [1] : []
    content {
      sid    = "AllowHCPEC2Service"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.is_hcp_cluster ? [1] : []
    content {
      sid    = "AllowHCPEC2CreateGrant"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.is_hcp_cluster ? [1] : []
    content {
      sid    = "AllowHCPAutoScaling"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["autoscaling.amazonaws.com"]
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.is_hcp_cluster ? [1] : []
    content {
      sid    = "AllowHCPAutoScalingCreateGrant"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["autoscaling.amazonaws.com"]
      }
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.is_hcp_cluster ? [1] : []
    content {
      sid    = "AllowHCPCAPAControllerManager"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions = [
        "kms:DescribeKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:CreateGrant",
      ]
      resources = ["*"]
      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.operator_role_prefix}-kube-system-capa-controller-manager",
        ]
      }
    }
  }

  #--------------------------------------------------------------------------
  # HCP etcd Encryption (only when explicitly enabled)
  #--------------------------------------------------------------------------

  dynamic "statement" {
    for_each = var.enable_hcp_etcd_encryption ? [1] : []
    content {
      sid    = "AllowHCPKubeControllerManager"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = ["kms:DescribeKey"]
      resources = ["*"]
      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.operator_role_prefix}-kube-system-kube-controller-manager",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_hcp_etcd_encryption ? [1] : []
    content {
      sid    = "AllowHCPKMSProvider"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = ["*"]
      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.operator_role_prefix}-kube-system-kms-provider",
        ]
      }
    }
  }
}

#==============================================================================
# INFRASTRUCTURE KMS KEY
# For non-ROSA resources: jump host, CloudWatch, S3/OADP, VPN logs
#
# IMPORTANT: This key does NOT have ROSA role permissions.
# This is intentional to maintain strict separation and blast radius containment.
#==============================================================================

resource "aws_kms_key" "infrastructure" {
  count = local.create_infra_key ? 1 : 0

  description              = "Infrastructure KMS key for ${var.cluster_name} - non-ROSA resources"
  deletion_window_in_days  = var.kms_key_deletion_window
  enable_key_rotation      = true
  is_enabled               = true
  multi_region             = false
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage                = "ENCRYPT_DECRYPT"

  policy = data.aws_iam_policy_document.infra_kms_policy[0].json

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-infra-kms"
      Purpose = "infrastructure-encryption"
      Scope   = "jumphost-cloudwatch-s3-vpn"
    }
  )
}

resource "aws_kms_alias" "infrastructure" {
  count = local.create_infra_key ? 1 : 0

  name          = "alias/${var.cluster_name}-infra"
  target_key_id = aws_kms_key.infrastructure[0].key_id
}

#------------------------------------------------------------------------------
# Infrastructure KMS Key Policy
# IMPORTANT: This policy is for NON-ROSA resources only.
# DO NOT add ROSA account/operator role permissions here.
#
# checkov:skip=CKV_AWS_109:KMS key policy resources="*" refers to this key only
# checkov:skip=CKV_AWS_111:KMS key policy resources="*" refers to this key only
# checkov:skip=CKV_AWS_356:KMS key policy resources="*" refers to this key only
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "infra_kms_policy" {
  count = local.create_infra_key ? 1 : 0

  #--------------------------------------------------------------------------
  # Root Account Access (Required for key administration)
  #--------------------------------------------------------------------------

  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  #--------------------------------------------------------------------------
  # CloudWatch Logs Service
  # For VPC flow logs, VPN connection logs, application logs
  #--------------------------------------------------------------------------

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
      ]
    }
  }

  #--------------------------------------------------------------------------
  # S3 Service
  # For OADP backups, other S3 bucket encryption
  #--------------------------------------------------------------------------

  statement {
    sid    = "AllowS3Service"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  #--------------------------------------------------------------------------
  # EC2 Service (for jump host EBS encryption)
  # NOTE: This is for jump host ONLY, not ROSA workers
  #--------------------------------------------------------------------------

  statement {
    sid    = "AllowEC2ForJumphost"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEC2CreateGrantForJumphost"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------

check "cluster_existing_mode_requires_arn" {
  assert {
    condition     = var.cluster_kms_mode != "existing" || var.cluster_kms_key_arn != null
    error_message = "cluster_kms_key_arn is required when cluster_kms_mode = \"existing\""
  }
}

check "infra_existing_mode_requires_arn" {
  assert {
    condition     = var.infra_kms_mode != "existing" || var.infra_kms_key_arn != null
    error_message = "infra_kms_key_arn is required when infra_kms_mode = \"existing\""
  }
}

check "cluster_create_mode_requires_prefixes" {
  assert {
    condition     = var.cluster_kms_mode != "create" || (var.account_role_prefix != "" && var.operator_role_prefix != "")
    error_message = "account_role_prefix and operator_role_prefix are required when cluster_kms_mode = \"create\""
  }
}
