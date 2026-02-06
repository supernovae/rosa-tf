#------------------------------------------------------------------------------
# OADP Resources Module for ROSA Classic GovCloud
#
# This module creates the AWS resources required for OpenShift API for Data
# Protection (OADP), which provides backup and restore capabilities using Velero.
#
# Resources created:
# - S3 bucket for backup storage (with versioning and encryption)
# - IAM role with OIDC trust for the OADP service account
# - IAM policy with S3 and EC2 permissions for Velero
#
# The OADP operator and configuration are deployed via GitOps using the
# rosa-gitops-config ConfigMap for values.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Local Variables
#------------------------------------------------------------------------------

locals {
  # S3 bucket naming - must be DNS compliant (3-63 chars, lowercase, no consecutive hyphens)
  # Pattern: {cluster_name}-{account_id}-oadp-backups
  # Account ID = 12 chars, suffix = 12 chars, hyphens = 2 → max cluster_name = 37 chars
  bucket_suffix       = "oadp-backups"
  bucket_max_name_len = 63 - 12 - length(local.bucket_suffix) - 2 # 37 chars for cluster name
  bucket_cluster_name = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name         = "${local.bucket_cluster_name}-${data.aws_caller_identity.current.account_id}-${local.bucket_suffix}"
}

#------------------------------------------------------------------------------
# S3 Bucket for OADP Backups
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "oadp" {
  # DNS-compliant bucket name with account ID for global uniqueness
  bucket = local.bucket_name

  # force_destroy = false means non-empty buckets fail with "BucketNotEmpty"
  # This protects data while allowing terraform destroy to proceed after cleanup
  force_destroy = false

  tags = merge(
    var.tags,
    {
      Name                      = local.bucket_name
      "rosa-gitops-layer"       = "oadp"
      "velero.io/backup-bucket" = "true"
    }
  )
}

resource "aws_s3_bucket_versioning" "oadp" {
  bucket = aws_s3_bucket.oadp.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "oadp" {
  bucket = aws_s3_bucket.oadp.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "oadp" {
  bucket = aws_s3_bucket.oadp.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "oadp" {
  count  = var.backup_retention_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.oadp.id

  # Abort incomplete multipart uploads after 7 days (CKV_AWS_300)
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "backup-retention"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }

  rule {
    id     = "restic-retention"
    status = "Enabled"

    filter {
      prefix = "restic/"
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
}

#------------------------------------------------------------------------------
# IAM Role for OADP Operator
# Uses OIDC federation to allow the Velero service account to assume this role
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "oadp_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.oidc_endpoint_url}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_endpoint_url}:sub"
      values = [
        "system:serviceaccount:openshift-adp:openshift-adp-controller-manager",
        "system:serviceaccount:openshift-adp:velero"
      ]
    }
  }
}

resource "aws_iam_role" "oadp" {
  name               = "${var.cluster_name}-oadp"
  assume_role_policy = data.aws_iam_policy_document.oadp_trust.json
  path               = var.iam_role_path

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-oadp"
      "rosa-gitops-layer" = "oadp"
      "red-hat-managed"   = "false"
    }
  )
}

#------------------------------------------------------------------------------
# IAM Policy for OADP/Velero
# Provides permissions for S3 backup storage and EC2 snapshot operations
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "oadp" {
  # S3 permissions for backup storage
  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [aws_s3_bucket.oadp.arn]
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.oadp.arn}/*"]
  }

  # EC2 permissions for volume snapshots
  statement {
    sid    = "EC2SnapshotAccess"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot"
    ]
    resources = ["*"]
  }

  # KMS permissions (if using KMS encryption)
  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSAccess"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "oadp" {
  name   = "${var.cluster_name}-oadp-policy"
  role   = aws_iam_role.oadp.id
  policy = data.aws_iam_policy_document.oadp.json
}

#------------------------------------------------------------------------------
# Wait for IAM role propagation
#------------------------------------------------------------------------------

resource "time_sleep" "role_propagation" {
  create_duration = "10s"

  triggers = {
    role_arn = aws_iam_role.oadp.arn
  }

  depends_on = [aws_iam_role_policy.oadp]
}
