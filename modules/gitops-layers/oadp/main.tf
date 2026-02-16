#------------------------------------------------------------------------------
# OADP Resources Module for ROSA
#
# This module creates the AWS resources required for OpenShift API for Data
# Protection (OADP), which provides backup and restore capabilities using Velero.
#
# Resources created:
# - S3 bucket for backup storage (via CloudFormation with DeletionPolicy: Retain)
# - IAM role with OIDC trust for the OADP service account
# - IAM policy with S3 and EC2 permissions for Velero
#
# S3 LIFECYCLE:
# The S3 bucket is created via CloudFormation with DeletionPolicy: Retain.
# On terraform destroy, the CloudFormation stack is deleted but the bucket
# is retained (not deleted). This avoids BucketNotEmpty errors and preserves
# backup data. Users must manually delete the bucket when ready.
#
# The OADP operator and configuration are deployed by the operator module
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
  # Pattern: {cluster_name}-{random_8hex}-oadp-backups
  # Random ID provides global uniqueness without leaking AWS account ID
  bucket_suffix       = "oadp-backups"
  bucket_max_name_len = 63 - 8 - length(local.bucket_suffix) - 2 # 8 chars for random hex
  bucket_cluster_name = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name         = "${local.bucket_cluster_name}-${random_id.bucket_suffix.hex}-${local.bucket_suffix}"

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
# S3 Bucket for OADP Backups (via CloudFormation with DeletionPolicy: Retain)
#
# Using CloudFormation ensures the bucket is RETAINED when terraform destroy
# runs. This avoids BucketNotEmpty errors and preserves backup data.
#------------------------------------------------------------------------------

resource "aws_cloudformation_stack" "oadp_bucket" {
  name = "${var.cluster_name}-oadp-bucket"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "S3 bucket for OADP backup storage (${var.cluster_name}). DeletionPolicy: Retain ensures bucket survives stack deletion."

    Resources = {
      OADPBucket = {
        Type                = "AWS::S3::Bucket"
        DeletionPolicy      = "Retain"
        UpdateReplacePolicy = "Retain"
        Properties = merge(
          {
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
            Tags = concat(
              [
                { Key = "Name", Value = local.bucket_name },
                { Key = "rosa-gitops-layer", Value = "oadp" },
                { Key = "velero.io/backup-bucket", Value = "true" }
              ],
              [for k, v in var.tags : { Key = k, Value = v }]
            )
          },
          var.backup_retention_days > 0 ? {
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
                  Id               = "backup-retention"
                  Status           = "Enabled"
                  Prefix           = "backups/"
                  ExpirationInDays = var.backup_retention_days
                  NoncurrentVersionExpiration = {
                    NoncurrentDays = var.backup_retention_days
                  }
                },
                {
                  Id               = "restic-retention"
                  Status           = "Enabled"
                  Prefix           = "restic/"
                  ExpirationInDays = var.backup_retention_days
                  NoncurrentVersionExpiration = {
                    NoncurrentDays = var.backup_retention_days
                  }
                }
              ]
            }
          } : {}
        )
      }
    }

    Outputs = {
      BucketName = {
        Value = { Ref = "OADPBucket" }
      }
      BucketArn = {
        Value = { "Fn::GetAtt" = ["OADPBucket", "Arn"] }
      }
    }
  })

  tags = merge(
    var.tags,
    {
      "rosa-gitops-layer" = "oadp"
    }
  )
}

#------------------------------------------------------------------------------
# Destroy-time notice: remind user to clean up the retained bucket
#------------------------------------------------------------------------------

resource "null_resource" "bucket_destroy_notice" {
  triggers = {
    bucket_name = local.bucket_name
    aws_region  = data.aws_region.current.id
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

  The OADP backup bucket was NOT deleted.
  It has been retained for data safety.

  To delete when you no longer need the backups:

    # Step 1: List and delete all object versions
    aws s3api list-object-versions \
      --bucket <BUCKET_NAME> \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
      --output json --region <REGION> \
      | aws s3api delete-objects \
        --bucket <BUCKET_NAME> \
        --delete file:///dev/stdin \
        --region <REGION>

    # Step 2: Delete the empty bucket
    aws s3 rb s3://<BUCKET_NAME> --region <REGION>

=============================================
NOTICE
      echo "  Bucket: $BUCKET"
      echo "  Region: $REGION"
      echo ""
    EOT
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
    resources = [local.bucket_arn]
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
    resources = ["${local.bucket_arn}/*"]
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
