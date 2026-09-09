# S3 recovery repository and exact OIDC identity. CSI snapshots are managed by
# the cluster storage driver, so the Velero role needs no EC2 snapshot grants.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  bucket_suffix       = "oadp-backups"
  bucket_max_name_len = 63 - 8 - length(local.bucket_suffix) - 2
  bucket_cluster_name = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name         = "${local.bucket_cluster_name}-${random_id.bucket_suffix.hex}-${local.bucket_suffix}"
  bucket_arn          = "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_name}"
  oidc_issuer         = trimsuffix(trimprefix(var.oidc_endpoint_url, "https://"), "/")
}
resource "random_id" "bucket_suffix" {
  byte_length = 4
  keepers     = { cluster_name = var.cluster_name }
}
resource "aws_cloudformation_stack" "oadp_bucket" {
  name = "${var.cluster_name}-oadp-bucket"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Retained OADP repository. Velero TTL and repository maintenance own data expiration."
    Resources = {
      OADPBucket = {
        Type                = "AWS::S3::Bucket"
        DeletionPolicy      = "Retain"
        UpdateReplacePolicy = "Retain"
        Properties = {
          BucketName              = local.bucket_name
          VersioningConfiguration = { Status = "Enabled" }
          OwnershipControls       = { Rules = [{ ObjectOwnership = "BucketOwnerEnforced" }] }
          BucketEncryption = {
            ServerSideEncryptionConfiguration = [{
              ServerSideEncryptionByDefault = var.kms_key_arn != null ? {
                SSEAlgorithm = "aws:kms", KMSMasterKeyID = var.kms_key_arn
              } : { SSEAlgorithm = "AES256" }
              BucketKeyEnabled = var.kms_key_arn != null
            }]
          }
          PublicAccessBlockConfiguration = {
            BlockPublicAcls  = true, BlockPublicPolicy = true
            IgnorePublicAcls = true, RestrictPublicBuckets = true
          }
          # Never expire live backup metadata or shared Kopia chunks by object age.
          LifecycleConfiguration = {
            Rules = [{
              Id                             = "abort-incomplete-uploads"
              Status                         = "Enabled"
              AbortIncompleteMultipartUpload = { DaysAfterInitiation = 7 }
            }]
          }
          Tags = concat([
            { Key = "Name", Value = local.bucket_name },
            { Key = "rosa-gitops-layer", Value = "oadp" },
            { Key = "velero.io/backup-bucket", Value = "true" }
          ], [for k, v in var.tags : { Key = k, Value = v }])
        }
      }
      OADPBucketPolicy = {
        Type = "AWS::S3::BucketPolicy"
        Properties = {
          Bucket = { Ref = "OADPBucket" }
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
    }
    Outputs = {
      BucketName = { Value = { Ref = "OADPBucket" } }
      BucketArn  = { Value = { "Fn::GetAtt" = ["OADPBucket", "Arn"] } }
    }
  })
  tags = merge(var.tags, { "rosa-gitops-layer" = "oadp" })
  lifecycle { prevent_destroy = true }
}

# Remove the obsolete destroy-time shell notice without running its provisioner.
removed {
  from = null_resource.bucket_destroy_notice
  lifecycle { destroy = false }
}

data "aws_iam_policy_document" "oadp_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_issuer}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values = [
        "system:serviceaccount:openshift-adp:openshift-adp-controller-manager",
        "system:serviceaccount:openshift-adp:velero"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      # OADP's documented projected token audience (not EKS's sts.amazonaws.com).
      values = ["openshift"]
    }
  }
}
resource "aws_iam_role" "oadp" {
  name               = "${var.cluster_name}-oadp"
  assume_role_policy = data.aws_iam_policy_document.oadp_trust.json
  path               = var.iam_role_path
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oadp", "rosa-gitops-layer" = "oadp", "red-hat-managed" = "false"
  })
}
data "aws_iam_policy_document" "oadp" {
  statement {
    sid       = "S3BucketAccess"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
    resources = [local.bucket_arn]
  }
  statement {
    sid     = "S3RepositoryAccess"
    effect  = "Allow"
    actions = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:ListMultipartUploadParts", "s3:PutObject"]
    # Preserve the existing DPA repository prefix. No bucket-wide object grants.
    resources = ["${local.bucket_arn}/velero/*"]
  }
  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "KMSRepositoryAccess"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      resources = [var.kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }
}
resource "aws_iam_role_policy" "oadp" {
  name   = "${var.cluster_name}-oadp-policy"
  role   = aws_iam_role.oadp.id
  policy = data.aws_iam_policy_document.oadp.json
}
resource "time_sleep" "role_propagation" {
  create_duration = "10s"
  triggers        = { role_arn = aws_iam_role.oadp.arn }
  depends_on      = [aws_iam_role_policy.oadp]
}
