#------------------------------------------------------------------------------
# OpenShift AI Resources Module
#
# Creates the AWS resources required for Red Hat OpenShift AI:
#
# - S3 bucket for model artifacts, pipeline data, and data connections
#   (via CloudFormation with DeletionPolicy: Retain)
# - IAM role with OIDC trust for RHOAI service accounts
# - IAM policy with S3 permissions
#
# S3 LIFECYCLE:
# The S3 bucket is created via CloudFormation with DeletionPolicy: Retain.
# On terraform destroy, the CloudFormation stack is deleted but the bucket
# is retained (not deleted). This preserves model data and pipeline artifacts.
# Users must manually delete the bucket when ready.
#
# The operators (NFD, NVIDIA GPU, RHOAI) are deployed by the operator module.
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
  bucket_suffix         = "rhoai-data"
  bucket_max_name_len   = 63 - 8 - length(local.bucket_suffix) - 2
  bucket_cluster_name   = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name_generated = "${local.bucket_cluster_name}-${random_id.bucket_suffix.hex}-${local.bucket_suffix}"
  bucket_name           = var.s3_bucket_name != "" ? var.s3_bucket_name : local.bucket_name_generated

  s3_endpoint = "s3.${var.aws_region}.amazonaws.com"

  # RHOAI service accounts that need S3 access for data connections and pipelines
  rhoai_service_accounts = [
    "system:serviceaccount:redhat-ods-applications:*",
    "system:serviceaccount:rhods-notebooks:*"
  ]

  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_name}"
}

#------------------------------------------------------------------------------
# Random ID for Bucket Naming
#------------------------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4

  keepers = {
    cluster_name = var.cluster_name
  }
}

#------------------------------------------------------------------------------
# S3 Bucket for RHOAI Data (via CloudFormation with DeletionPolicy: Retain)
#------------------------------------------------------------------------------

resource "aws_cloudformation_stack" "rhoai_bucket" {
  name = "${var.cluster_name}-rhoai-bucket"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "S3 bucket for OpenShift AI data (${var.cluster_name}). DeletionPolicy: Retain ensures bucket survives stack deletion."

    Resources = {
      RhoaiBucket = {
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
            Rules = concat(
              [
                {
                  Id     = "abort-incomplete-uploads"
                  Status = "Enabled"
                  AbortIncompleteMultipartUpload = {
                    DaysAfterInitiation = 7
                  }
                }
              ],
              var.data_retention_days > 0 ? [
                {
                  Id               = "data-retention"
                  Status           = "Enabled"
                  ExpirationInDays = var.data_retention_days
                  NoncurrentVersionExpiration = {
                    NoncurrentDays = var.data_retention_days
                  }
                }
              ] : []
            )
          }
          Tags = concat(
            [
              { Key = "Name", Value = local.bucket_name },
              { Key = "rosa-gitops-layer", Value = "openshift-ai" },
              { Key = "rhoai.opendatahub.io", Value = "data-storage" }
            ],
            [for k, v in var.tags : { Key = k, Value = v }]
          )
        }
      }
    }

    Outputs = {
      BucketName = {
        Value = { Ref = "RhoaiBucket" }
      }
      BucketArn = {
        Value = { "Fn::GetAtt" = ["RhoaiBucket", "Arn"] }
      }
    }
  })

  tags = merge(
    var.tags,
    {
      "rosa-gitops-layer" = "openshift-ai"
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
  S3 BUCKET RETAINED (OpenShift AI)
=============================================

  The RHOAI data bucket was NOT deleted.
  It has been retained for data safety.

  To delete when you no longer need the data:

    aws s3 rb s3://<BUCKET_NAME> --force --region <REGION>

=============================================
NOTICE
      echo "  Bucket: $BUCKET"
      echo "  Region: $REGION"
      echo ""
    EOT
  }
}

#------------------------------------------------------------------------------
# IAM Role for RHOAI Workloads
# Uses OIDC federation for IRSA
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "rhoai_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.oidc_endpoint_url}"]
    }

    condition {
      test     = "StringLike"
      variable = "${var.oidc_endpoint_url}:sub"
      values   = local.rhoai_service_accounts
    }
  }
}

resource "aws_iam_role" "rhoai" {
  name               = "${var.cluster_name}-rhoai"
  assume_role_policy = data.aws_iam_policy_document.rhoai_trust.json
  path               = var.iam_role_path

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-rhoai"
      "rosa-gitops-layer" = "openshift-ai"
      "red-hat-managed"   = "false"
    }
  )
}

#------------------------------------------------------------------------------
# IAM Policy for RHOAI S3 Access
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "rhoai" {
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

resource "aws_iam_role_policy" "rhoai" {
  name   = "${var.cluster_name}-rhoai-policy"
  role   = aws_iam_role.rhoai.id
  policy = data.aws_iam_policy_document.rhoai.json
}

#------------------------------------------------------------------------------
# Wait for IAM role propagation
#------------------------------------------------------------------------------

resource "time_sleep" "role_propagation" {
  create_duration = "10s"

  triggers = {
    role_arn = aws_iam_role.rhoai.arn
  }

  depends_on = [aws_iam_role_policy.rhoai]
}
