#------------------------------------------------------------------------------
# Cert-Manager Resources Module for ROSA
#
# This module creates the AWS resources required for cert-manager to perform
# DNS01 challenges against Route53 for Let's Encrypt certificate automation.
#
# It provides:
# - IAM role with OIDC trust for the cert-manager service account (IRSA)
# - IAM policy with Route53 permissions for DNS01 challenge
# - Optional Route53 hosted zone creation
#
# IMPORTANT: This module requires outbound internet access for the DNS01
# challenge to reach Let's Encrypt ACME servers. It CANNOT be used on
# zero-egress clusters. Use cert_mode=provided for air-gapped environments.
#
# The cert-manager operator and configuration are deployed by the operator
# module using native kubernetes/kubectl providers with templatefile().
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

#------------------------------------------------------------------------------
# Local Variables
#------------------------------------------------------------------------------

locals {
  # cert-manager service account that needs Route53 access
  # The cert-manager operator creates this SA in the cert-manager namespace
  certmanager_service_account = "system:serviceaccount:cert-manager:cert-manager"

  # Determine the hosted zone ID to use (created or provided)
  effective_hosted_zone_id = var.create_hosted_zone ? aws_route53_zone.certmanager[0].zone_id : var.hosted_zone_id

  # Determine the hosted zone domain
  effective_hosted_zone_domain = var.create_hosted_zone ? var.hosted_zone_domain : (
    length(data.aws_route53_zone.existing) > 0 ? data.aws_route53_zone.existing[0].name : var.hosted_zone_domain
  )

  # Determine the ingress domain (what the IngressController serves)
  # Default: apps.<hosted_zone_domain>  Override: whatever the user sets
  effective_ingress_domain = var.ingress_domain != "" ? var.ingress_domain : "apps.${local.effective_hosted_zone_domain}"
}

#------------------------------------------------------------------------------
# Route53 Hosted Zone (Optional)
# Created only when create_hosted_zone = true
#------------------------------------------------------------------------------

resource "aws_route53_zone" "certmanager" {
  count = var.create_hosted_zone ? 1 : 0

  name    = var.hosted_zone_domain
  comment = "Managed by Terraform for cert-manager DNS01 challenges (${var.cluster_name})"

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-certmanager"
      "rosa-gitops-layer" = "certmanager"
    }
  )
}

#------------------------------------------------------------------------------
# DNSSEC Signing (enabled by default when creating a hosted zone)
#
# Enables DNSSEC signing on the Route53 hosted zone to protect against
# DNS spoofing and cache poisoning. Uses a customer-managed KMS key for
# the Key Signing Key (KSK). Route53 manages Zone Signing Keys (ZSKs)
# automatically.
#
# NOTE: After enabling, you must add a DS record to the parent zone
# (your domain registrar) to complete the chain of trust. The DS record
# value is available in the outputs.
#
# For GovCloud, the KMS key must be in the same region as Route53.
# For Commercial, Route53 DNSSEC requires the KMS key in us-east-1.
#------------------------------------------------------------------------------

resource "aws_kms_key" "dnssec" {
  #checkov:skip=CKV_AWS_7:DNSSEC requires asymmetric ECC_NIST_P256 key which does not support automatic rotation. Route53 handles ZSK rotation automatically.
  count = var.create_hosted_zone && var.enable_dnssec ? 1 : 0

  # Route53 DNSSEC requires an asymmetric ECC_NIST_P256 key
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7
  description              = "DNSSEC KSK for ${var.hosted_zone_domain} (${var.cluster_name})"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowRoute53DNSSEC"
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowRoute53CreateGrant"
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Action   = "kms:CreateGrant"
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-dnssec-ksk"
      "rosa-gitops-layer" = "certmanager"
    }
  )
}

resource "aws_kms_alias" "dnssec" {
  count = var.create_hosted_zone && var.enable_dnssec ? 1 : 0

  name          = "alias/${var.cluster_name}-dnssec-ksk"
  target_key_id = aws_kms_key.dnssec[0].key_id
}

resource "aws_route53_key_signing_key" "certmanager" {
  count = var.create_hosted_zone && var.enable_dnssec ? 1 : 0

  hosted_zone_id             = aws_route53_zone.certmanager[0].zone_id
  key_management_service_arn = aws_kms_key.dnssec[0].arn
  name                       = "${var.cluster_name}-ksk"
}

resource "aws_route53_hosted_zone_dnssec" "certmanager" {
  count = var.create_hosted_zone && var.enable_dnssec ? 1 : 0

  hosted_zone_id = aws_route53_key_signing_key.certmanager[0].hosted_zone_id
  signing_status = "SIGNING"

  depends_on = [aws_route53_key_signing_key.certmanager]
}

#------------------------------------------------------------------------------
# DNS Query Logging
#
# Logs DNS queries to CloudWatch Logs for security monitoring and
# troubleshooting. Checkov CKV2_AWS_39 requires this for public zones.
#
# NOTE: For Commercial AWS, Route53 query logging requires the
# CloudWatch log group to be in us-east-1. If this module is deployed
# in a different region, query logging will fail. Set
# enable_query_logging = false for non-us-east-1 commercial deployments.
# For GovCloud, the log group is created in the deployment region.
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "query_logging" {
  count = var.create_hosted_zone && var.enable_query_logging ? 1 : 0

  name              = "/aws/route53/${var.hosted_zone_domain}"
  retention_in_days = var.query_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-route53-query-logs"
      "rosa-gitops-layer" = "certmanager"
    }
  )
}

resource "aws_cloudwatch_log_resource_policy" "query_logging" {
  count = var.create_hosted_zone && var.enable_query_logging ? 1 : 0

  policy_name = "${var.cluster_name}-route53-query-logging"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Route53QueryLogging"
        Effect = "Allow"
        Principal = {
          Service = "route53.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/route53/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_route53_query_log" "certmanager" {
  count = var.create_hosted_zone && var.enable_query_logging ? 1 : 0

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.query_logging[0].arn
  zone_id                  = aws_route53_zone.certmanager[0].zone_id

  depends_on = [aws_cloudwatch_log_resource_policy.query_logging]
}

#------------------------------------------------------------------------------
# Look up existing Route53 Hosted Zone (when not creating)
#------------------------------------------------------------------------------

data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : (var.hosted_zone_id != "" ? 1 : 0)

  zone_id = var.hosted_zone_id
}

#------------------------------------------------------------------------------
# IAM Role for cert-manager
# Uses OIDC federation to allow cert-manager SA to assume this role
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "certmanager_trust" {
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
      values   = [local.certmanager_service_account]
    }
  }
}

resource "aws_iam_role" "certmanager" {
  name               = "${var.cluster_name}-certmanager"
  assume_role_policy = data.aws_iam_policy_document.certmanager_trust.json
  path               = var.iam_role_path

  tags = merge(
    var.tags,
    {
      Name                = "${var.cluster_name}-certmanager"
      "rosa-gitops-layer" = "certmanager"
      "red-hat-managed"   = "false"
    }
  )
}

#------------------------------------------------------------------------------
# IAM Policy for cert-manager
# Provides Route53 permissions for DNS01 challenge resolution
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "certmanager" {
  # Permission to check propagation of DNS changes
  statement {
    sid    = "Route53GetChange"
    effect = "Allow"
    actions = [
      "route53:GetChange"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }

  # Permission to create/delete TXT records for DNS01 challenge
  # Scoped to the specific hosted zone for least-privilege
  statement {
    sid    = "Route53RecordSets"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${local.effective_hosted_zone_id}"]
  }

  # Permission to discover hosted zones (required by cert-manager)
  statement {
    sid    = "Route53ListZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "certmanager" {
  name   = "${var.cluster_name}-certmanager-policy"
  role   = aws_iam_role.certmanager.id
  policy = data.aws_iam_policy_document.certmanager.json
}

#------------------------------------------------------------------------------
# Wait for IAM role propagation
#------------------------------------------------------------------------------

resource "time_sleep" "role_propagation" {
  create_duration = "10s"

  triggers = {
    role_arn = aws_iam_role.certmanager.arn
  }

  depends_on = [aws_iam_role_policy.certmanager]
}
