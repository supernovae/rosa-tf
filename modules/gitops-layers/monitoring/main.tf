#------------------------------------------------------------------------------
# Monitoring Resources Module for ROSA
#
# This module creates the AWS resources required for OpenShift monitoring
# and logging with Loki. It provides:
#
# - S3 bucket for Loki log storage (via CloudFormation with DeletionPolicy: Retain)
# - IAM role with OIDC trust for the Loki service account
# - IAM policy with S3 permissions for Loki
#
# S3 LIFECYCLE:
# The S3 bucket is created via CloudFormation with DeletionPolicy: Retain.
# On terraform destroy, the CloudFormation stack is deleted but the bucket
# is retained (not deleted). This avoids BucketNotEmpty errors and preserves
# log data for compliance. Users must manually delete the bucket when ready.
#
# The monitoring operators and configuration are deployed by the operator module
# using native kubernetes/kubectl providers with templatefile().
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
  # Pattern: {cluster_name}-{random_8hex}-loki-logs
  # Random ID provides global uniqueness without leaking AWS account ID
  bucket_suffix         = "loki-logs"
  bucket_max_name_len   = 63 - 8 - length(local.bucket_suffix) - 2 # 8 chars for random hex
  bucket_cluster_name   = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name_generated = "${local.bucket_cluster_name}-${random_id.bucket_suffix.hex}-${local.bucket_suffix}"
  bucket_name           = var.s3_bucket_name != "" ? var.s3_bucket_name : local.bucket_name_generated

  # S3 endpoint URL varies by partition
  # GovCloud: s3.us-gov-west-1.amazonaws.com
  # Commercial: s3.us-east-1.amazonaws.com
  s3_endpoint = "s3.${var.aws_region}.amazonaws.com"

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

  # Bucket ARN is constructed from the name since CloudFormation outputs
  # the bucket name and we derive the ARN from it
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_name}"
}

#------------------------------------------------------------------------------
# Random ID for Bucket Naming
# Provides global uniqueness without exposing AWS account ID
#------------------------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4 # 8 hex characters

  keepers = {
    cluster_name = var.cluster_name
  }
}

#------------------------------------------------------------------------------
# S3 Bucket for Loki Logs (via CloudFormation with DeletionPolicy: Retain)
#
# Using CloudFormation ensures the bucket is RETAINED when terraform destroy
# runs. This avoids BucketNotEmpty errors and preserves log data.
#------------------------------------------------------------------------------

resource "aws_cloudformation_stack" "loki_bucket" {
  name = "${var.cluster_name}-loki-bucket"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "S3 bucket for Loki log storage (${var.cluster_name}). DeletionPolicy: Retain ensures bucket survives stack deletion."

    Resources = {
      LokiBucketPolicy = {
        Type = "AWS::S3::BucketPolicy"
        Properties = {
          Bucket = { Ref = "LokiBucket" }
          PolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Sid       = "DenyInsecureTransport"
              Effect    = "Deny"
              Principal = "*"
              Action    = "s3:*"
              Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
              Condition = { Bool = { "aws:SecureTransport" = "false" } }
            }]
          }
        }
      }
      LokiBucket = {
        Type                = "AWS::S3::Bucket"
        DeletionPolicy      = "Retain"
        UpdateReplacePolicy = "Retain"
        Properties = {
          BucketName = local.bucket_name
          VersioningConfiguration = {
            Status = "Enabled"
          }
          BucketEncryption = {
            ServerSideEncryptionConfiguration = [
              {
                ServerSideEncryptionByDefault = var.kms_key_arn != null ? {
                  SSEAlgorithm   = "aws:kms"
                  KMSMasterKeyID = var.kms_key_arn
                  } : {
                  SSEAlgorithm = "AES256"
                }
                BucketKeyEnabled = var.kms_key_arn != null
              }
            ]
          }
          PublicAccessBlockConfiguration = {
            BlockPublicAcls       = true
            BlockPublicPolicy     = true
            IgnorePublicAcls      = true
            RestrictPublicBuckets = true
          }
          LifecycleConfiguration = {
            Rules = [
              {
                Id     = "abort-incomplete-uploads"
                Status = "Enabled"
                AbortIncompleteMultipartUpload = {
                  DaysAfterInitiation = 7
                }
              },
              {
                # Only Loki's compactor expires current chunks AND indexes.
                # Independent object expiry can corrupt otherwise queryable logs.
                Id     = "noncurrent-version-retention"
                Status = "Enabled"
                NoncurrentVersionExpiration = {
                  NoncurrentDays = var.log_retention_days
                }
              },
              {
                Id                        = "expired-delete-markers"
                Status                    = "Enabled"
                ExpiredObjectDeleteMarker = true
              }
            ]
          }
          Tags = concat(
            [
              { Key = "Name", Value = local.bucket_name },
              { Key = "rosa-gitops-layer", Value = "monitoring" },
              { Key = "loki.grafana.com", Value = "storage" }
            ],
            [for k, v in var.tags : { Key = k, Value = v }]
          )
        }
      }
    }

    Outputs = {
      BucketName = {
        Value = { Ref = "LokiBucket" }
      }
      BucketArn = {
        Value = { "Fn::GetAtt" = ["LokiBucket", "Arn"] }
      }
    }
  })

  tags = merge(
    var.tags,
    {
      "rosa-gitops-layer" = "monitoring"
    }
  )
}

#------------------------------------------------------------------------------
# Destroy-time notice: remind user to clean up the retained bucket
#------------------------------------------------------------------------------

resource "null_resource" "bucket_destroy_notice" {
  triggers = {
    bucket_name = local.bucket_name
    aws_region  = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      BUCKET="${self.triggers.bucket_name}"
      REGION="${self.triggers.aws_region}"
      cat <<'NOTICE'

=============================================
  S3 BUCKET RETAINED
=============================================

  The Loki log storage bucket was NOT deleted.
  It has been retained for data safety.

  Before any manual cleanup, obtain retention/legal-hold approval.
  Inventory ALL versions and delete markers. Use a reviewed, paginated
  cleanup procedure; a one-shot delete-objects command is insufficient.
  See docs/OBSERVABILITY-AWS-RECOVERY.md. Retained data incurs charges.

=============================================
NOTICE
      echo "  Bucket: $BUCKET"
      echo "  Region: $REGION"
      echo ""
    EOT
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
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_endpoint_url}:aud"
      values   = ["sts.amazonaws.com"]
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
    resources = [local.bucket_arn]
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
    resources = ["${local.bucket_arn}/*"]
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
