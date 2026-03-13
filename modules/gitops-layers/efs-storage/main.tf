#------------------------------------------------------------------------------
# AWS EFS Storage Resources
#
# Creates the AWS infrastructure for EFS-backed dynamic PV provisioning:
# 1. EFS file system (encrypted, optional customer-managed KMS)
# 2. Security group allowing NFS (TCP 2049) from VPC CIDR
# 3. Mount targets in each private subnet
# 4. IAM role with OIDC trust for the EFS CSI driver controller SA
#
# GovCloud Parity:
#   All ARNs use data.aws_partition.current.partition for Commercial/GovCloud.
#   Encryption is always enabled (mandatory for FedRAMP).
#   Optional customer-managed KMS via var.kms_key_arn.
#
# Classic / HCP Parity:
#   No differentiation needed. OIDC endpoint and subnets are passed from
#   the environment layer which handles the cluster type differences.
#
# The Kubernetes resources (Subscription, ClusterCSIDriver, StorageClass)
# are managed by the operator module (layer-efs-storage.tf).
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id
}

#------------------------------------------------------------------------------
# 1. EFS File System
#------------------------------------------------------------------------------

resource "aws_efs_file_system" "this" {
  #checkov:skip=CKV_AWS_184:Encryption at rest is always enabled. CMK is optional via kms_key_arn (uses AWS-managed aws/elasticfilesystem key when unset). GovCloud environments pass the infra KMS key automatically.
  encrypted        = var.efs_encrypted
  kms_key_id       = var.kms_key_arn != "" ? var.kms_key_arn : null
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-efs"
    "rosa-gitops-layer" = "efs-storage"
  })
}

#------------------------------------------------------------------------------
# 2. Security Group (NFS ingress from VPC CIDR)
#------------------------------------------------------------------------------

resource "aws_security_group" "efs" {
  name        = "${var.cluster_name}-efs"
  description = "Allow NFS access from VPC for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-efs"
    "rosa-gitops-layer" = "efs-storage"
  })
}

#------------------------------------------------------------------------------
# 3. Mount Targets (one per private subnet)
#------------------------------------------------------------------------------

resource "aws_efs_mount_target" "this" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

#------------------------------------------------------------------------------
# 4. IAM Role for EFS CSI Driver (IRSA)
#
# The EFS CSI driver controller runs in openshift-cluster-csi-drivers and
# assumes this role via OIDC federation to manage EFS access points.
# No additional policies are needed on machine pools or Karpenter NodePools.
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "efs_csi_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${var.oidc_endpoint_url}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_endpoint_url}:sub"
      values = [
        "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-controller-sa",
        "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-operator",
      ]
    }
  }
}

resource "aws_iam_role" "efs_csi" {
  name               = "${var.cluster_name}-efs-csi"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_trust.json

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-efs-csi"
    "rosa-gitops-layer" = "efs-storage"
    "red-hat-managed"   = "false"
  })
}

data "aws_iam_policy_document" "efs_csi" {
  statement {
    sid    = "EFSDescribe"
    effect = "Allow"
    actions = [
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EFSCreateAccessPoint"
    effect = "Allow"
    actions = [
      "elasticfilesystem:CreateAccessPoint",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    sid    = "EFSTagResource"
    effect = "Allow"
    actions = [
      "elasticfilesystem:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EFSDeleteAccessPoint"
    effect = "Allow"
    actions = [
      "elasticfilesystem:DeleteAccessPoint",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    sid    = "EC2DescribeAZs"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "efs_csi" {
  name   = "${var.cluster_name}-efs-csi"
  policy = data.aws_iam_policy_document.efs_csi.json

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-efs-csi"
    "rosa-gitops-layer" = "efs-storage"
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = aws_iam_policy.efs_csi.arn
}
