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
# The cert-manager operator and configuration are deployed via the operator
# module using the rosa-gitops-config ConfigMap for values.
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
