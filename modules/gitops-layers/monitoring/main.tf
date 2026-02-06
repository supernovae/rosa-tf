#------------------------------------------------------------------------------
# Monitoring Resources Module for ROSA
#
# This module creates the AWS resources required for OpenShift monitoring
# and logging with Loki. It provides:
#
# - S3 bucket for Loki log storage (with versioning and encryption)
# - IAM role with OIDC trust for the Loki service account
# - IAM policy with S3 permissions for Loki
#
# The monitoring operators and configuration are deployed via GitOps using
# the rosa-gitops-config ConfigMap for values.
#
# Supports both:
# - GovCloud (4.16): logging.openshift.io/v1 API
# - Commercial (4.17+): observability.openshift.io/v1 API
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
  # Pattern: {cluster_name}-{account_id}-loki-logs
  # Account ID = 12 chars, suffix = 10 chars, hyphens = 2 → max cluster_name = 39 chars
  bucket_suffix         = "loki-logs"
  bucket_max_name_len   = 63 - 12 - length(local.bucket_suffix) - 2 # 39 chars for cluster name
  bucket_cluster_name   = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name_generated = "${local.bucket_cluster_name}-${data.aws_caller_identity.current.account_id}-${local.bucket_suffix}"
  bucket_name           = var.s3_bucket_name != "" ? var.s3_bucket_name : local.bucket_name_generated

  # S3 endpoint URL varies by partition
  # GovCloud: s3.us-gov-west-1.amazonaws.com
  # Commercial: s3.us-east-1.amazonaws.com
  s3_endpoint = var.is_govcloud ? "s3.${var.aws_region}.amazonaws.com" : "s3.${var.aws_region}.amazonaws.com"

  # Logging namespace - consistent across all supported versions
  # Minimum supported: OpenShift 4.16 with Logging Operator 6.x
  loki_namespace = "openshift-logging"

  # Loki service accounts that need S3 access
  # The Loki Operator creates service accounts based on the LokiStack CR name.
  # For LokiStack named "logging-loki", it creates:
  #   - logging-loki (main SA for all components)
  #   - logging-loki-ruler (separate SA for ruler component)
  # See: https://loki-operator.dev/docs/short_lived_tokens_authentication.md/
  loki_service_accounts = [
    "system:serviceaccount:${local.loki_namespace}:logging-loki",
    "system:serviceaccount:${local.loki_namespace}:logging-loki-ruler"
  ]
}

#------------------------------------------------------------------------------
# S3 Bucket for Loki Logs
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "loki" {
  bucket = local.bucket_name

  # force_destroy = false means non-empty buckets fail with "BucketNotEmpty"
  # This protects data while allowing terraform destroy to proceed after cleanup
  force_destroy = false

  tags = merge(
    var.tags,
    {
      Name                = local.bucket_name
      "rosa-gitops-layer" = "monitoring"
      "loki.grafana.com"  = "storage"
    }
  )
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  # Abort incomplete multipart uploads after 7 days
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Expire log chunks after retention period
  rule {
    id     = "log-retention"
    status = "Enabled"

    filter {
      prefix = "chunks/"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.log_retention_days
    }
  }

  # Expire index files after retention period
  rule {
    id     = "index-retention"
    status = "Enabled"

    filter {
      prefix = "index/"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.log_retention_days
    }
  }
}

#------------------------------------------------------------------------------
# IAM Role for Loki
# Uses OIDC federation to allow Loki service accounts to assume this role
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "loki_trust" {
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
      values   = local.loki_service_accounts
    }
  }
}

resource "aws_iam_role" "loki" {
  name               = "${var.cluster_name}-loki"
  assume_role_policy = data.aws_iam_policy_document.loki_trust.json
  path               = var.iam_role_path

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-loki"
      "rosa-gitops-layer" = "monitoring"
      "red-hat-managed"   = "false"
    }
  )
}

#------------------------------------------------------------------------------
# IAM Policy for Loki
# Provides permissions for S3 log storage
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "loki" {
  # S3 bucket-level permissions
  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [aws_s3_bucket.loki.arn]
  }

  # S3 object-level permissions
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
    resources = ["${aws_s3_bucket.loki.arn}/*"]
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

resource "aws_iam_role_policy" "loki" {
  name   = "${var.cluster_name}-loki-policy"
  role   = aws_iam_role.loki.id
  policy = data.aws_iam_policy_document.loki.json
}

#------------------------------------------------------------------------------
# Wait for IAM role propagation
#------------------------------------------------------------------------------

resource "time_sleep" "role_propagation" {
  create_duration = "10s"

  triggers = {
    role_arn = aws_iam_role.loki.arn
  }

  depends_on = [aws_iam_role_policy.loki]
}
