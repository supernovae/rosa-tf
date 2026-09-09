# Regional EFS for shared application files. The supported Red Hat operator owns
# the driver; Terraform owns the filesystem, network and controller identity.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_subnet" "mount" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

locals {
  partition   = data.aws_partition.current.partition
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  oidc_issuer = trimsuffix(trimprefix(var.oidc_endpoint_url, "https://"), "/")
  ap_arn      = "arn:${local.partition}:elasticfilesystem:${local.region}:${local.account_id}:access-point/*"
}

resource "aws_efs_file_system" "this" {
  #checkov:skip=CKV_AWS_184:Encryption is required; optional CMK is supplied by GovCloud infrastructure KMS.
  encrypted        = true
  kms_key_id       = var.kms_key_arn != "" ? var.kms_key_arn : null
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode
  tags             = merge(var.tags, { Name = "${var.cluster_name}-efs", "rosa-gitops-layer" = "efs-storage" })
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.efs_encrypted && var.efs_performance_mode == "generalPurpose" && contains(["elastic", "bursting"], var.efs_throughput_mode)
      error_message = "EFS requires encryption, generalPurpose performance and elastic or bursting throughput. Provisioned throughput needs a separately reviewed configuration."
    }
    precondition {
      condition     = length(var.efs_config.allowed_security_group_ids) > 0
      error_message = "Supply the actual EFS-consuming worker security groups; VPC-wide NFS access is no longer allowed."
    }
    precondition {
      condition = length(var.private_subnet_ids) > 0 && alltrue([
        for subnet in data.aws_subnet.mount : subnet.vpc_id == var.vpc_id
      ]) && length(distinct([for subnet in data.aws_subnet.mount : subnet.availability_zone_id])) == length(var.private_subnet_ids)
      error_message = "EFS needs exactly one mount-target subnet per selected AZ, all in the configured VPC. Preserve existing subnet ordering during migration."
    }
  }
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  backup_policy { status = "ENABLED" }
}

# Preserve the existing SG resource identity while narrowing its ingress.
# Stateful response traffic needs no outbound initiation rule on a mount target.
resource "aws_security_group" "efs" {
  name        = "${var.cluster_name}-efs"
  description = "Allow NFS access from VPC for EFS mount targets"
  vpc_id      = var.vpc_id
  ingress {
    description     = "TLS NFS from approved EFS worker security groups"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.efs_config.allowed_security_group_ids
  }
  egress = []
  tags   = merge(var.tags, { Name = "${var.cluster_name}-efs", "rosa-gitops-layer" = "efs-storage" })
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# The established regional CSI path uses TLS/access points and network isolation,
# not pod IAM authentication. Do not add the iam mount flag without a supported
# node-identity design. Access-point POSIX IDs are non-root and enforced by EFS.
data "aws_iam_policy_document" "filesystem" {
  statement {
    sid       = "AllowAccessPointClients"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.this.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
    condition {
      test     = "ArnLike"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [local.ap_arn]
    }
  }
  statement {
    sid       = "DenyPlaintext"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
    resources = [aws_efs_file_system.this.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid       = "DenyRoot"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientRootAccess"]
    resources = [aws_efs_file_system.this.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
  statement {
    sid       = "DenyMountWithoutAccessPoint"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.this.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "elasticfilesystem:AccessPointArn"
      values   = ["true"]
    }
  }
}
resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  policy         = data.aws_iam_policy_document.filesystem.json
}

data "aws_iam_policy_document" "efs_csi_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_issuer}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values = [
        "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-controller-sa",
        "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-operator"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["openshift"]
    }
  }
}
resource "aws_iam_role" "efs_csi" {
  name               = "${var.cluster_name}-efs-csi"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_trust.json
  tags               = merge(var.tags, { Name = "${var.cluster_name}-efs-csi", "rosa-gitops-layer" = "efs-storage", "red-hat-managed" = "false" })
}
data "aws_iam_policy_document" "efs_csi" {
  statement {
    sid       = "EFSDescribe"
    actions   = ["elasticfilesystem:DescribeAccessPoints", "elasticfilesystem:DescribeFileSystems", "elasticfilesystem:DescribeMountTargets", "ec2:DescribeAvailabilityZones"]
    resources = ["*"]
  }
  statement {
    sid       = "EFSCreateAccessPoint"
    actions   = ["elasticfilesystem:CreateAccessPoint"]
    resources = [aws_efs_file_system.this.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
  statement {
    sid       = "EFSTagNewAccessPoint"
    actions   = ["elasticfilesystem:TagResource"]
    resources = [local.ap_arn]
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:CreateAction"
      values   = ["CreateAccessPoint"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
  statement {
    # Allow Red Hat's tag reconciliation, not just creation-time tagging.
    # Do not restrict aws:TagKeys to the CSI tag: ROSA adds infrastructure tags.
    sid       = "EFSManageTaggedAccessPoint"
    actions   = ["elasticfilesystem:TagResource", "elasticfilesystem:DeleteAccessPoint"]
    resources = [local.ap_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
}
resource "aws_iam_policy" "efs_csi" {
  name   = "${var.cluster_name}-efs-csi"
  policy = data.aws_iam_policy_document.efs_csi.json
  tags   = merge(var.tags, { Name = "${var.cluster_name}-efs-csi", "rosa-gitops-layer" = "efs-storage" })
}
resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = aws_iam_policy.efs_csi.arn
}
