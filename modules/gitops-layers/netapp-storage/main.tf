#------------------------------------------------------------------------------
# NetApp Storage (FSx ONTAP) Resources Module for ROSA
#
# Provisions AWS FSx for NetApp ONTAP infrastructure for persistent storage
# on ROSA clusters. Creates:
#   - FSx ONTAP file system (Single-AZ or Multi-AZ)
#   - Storage Virtual Machine (SVM) for data access
#   - Security group allowing NFS (2049), iSCSI (3260), ONTAP mgmt (443)
#   - Optional dedicated subnets for FSxN endpoints
#   - IAM role with OIDC trust for the Trident CSI controller
#
# The Trident Operator, StorageClasses, and backend configuration are deployed
# by the operator module (layer-netapp-storage.tf) using kubernetes/kubectl.
#
# GovCloud Parity:
#   All ARNs use data.aws_partition.current.partition for Commercial/GovCloud.
#   Optional KMS encryption via var.kms_key_arn (required for FedRAMP).
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
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.name

  # Subnet selection: dedicated subnets if created, otherwise ROSA private subnets
  effective_subnet_ids = var.create_dedicated_subnets ? aws_subnet.fsx_ontap[*].id : var.private_subnet_ids

  # FSx ONTAP requires:
  #   SINGLE_AZ_1: exactly 1 subnet (preferred_subnet_id)
  #   MULTI_AZ_1:  2+ subnets (preferred + standby)
  preferred_subnet_id = local.effective_subnet_ids[0]

  # Auto-calculate dedicated subnet CIDRs from VPC CIDR if not provided.
  # Uses the last /28 blocks in the VPC range.
  auto_subnet_count = var.deployment_type == "MULTI_AZ_1" ? min(2, length(var.availability_zones)) : 1
  auto_subnet_cidrs = [
    for i in range(local.auto_subnet_count) :
    cidrsubnet(var.vpc_cidr, 12, pow(2, 12) - 1 - i)
  ]
  dedicated_subnet_cidrs = length(var.dedicated_subnet_cidrs) > 0 ? var.dedicated_subnet_cidrs : local.auto_subnet_cidrs
}

#------------------------------------------------------------------------------
# Security Group: FSx ONTAP
#
# Allows ROSA worker nodes to access FSxN endpoints via:
#   - TCP 443:  ONTAP REST API / management
#   - TCP 2049: NFS
#   - TCP 3260: iSCSI
#   - UDP 2049: NFS (statd, lockd)
#   - TCP 111:  NFS portmapper
#   - UDP 111:  NFS portmapper
#------------------------------------------------------------------------------

resource "aws_security_group" "fsx_ontap" {
  name_prefix = "${var.cluster_name}-fsx-ontap-"
  description = "FSx ONTAP access from ROSA workers (${var.cluster_name})"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-fsx-ontap"
    "rosa-gitops-layer" = "netapp-storage"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "fsx_ontap_mgmt" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "ONTAP REST API / management"
}

resource "aws_security_group_rule" "fsx_nfs_tcp" {
  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "NFS TCP"
}

resource "aws_security_group_rule" "fsx_nfs_udp" {
  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "NFS UDP"
}

resource "aws_security_group_rule" "fsx_iscsi" {
  type              = "ingress"
  from_port         = 3260
  to_port           = 3260
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "iSCSI"
}

resource "aws_security_group_rule" "fsx_portmapper_tcp" {
  type              = "ingress"
  from_port         = 111
  to_port           = 111
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "NFS portmapper TCP"
}

resource "aws_security_group_rule" "fsx_portmapper_udp" {
  type              = "ingress"
  from_port         = 111
  to_port           = 111
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "NFS portmapper UDP"
}

resource "aws_security_group_rule" "fsx_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "Egress to VPC"
}

#------------------------------------------------------------------------------
# Dedicated Subnets (Optional)
#
# When create_dedicated_subnets = true, creates /28 subnets in the same AZs
# as the ROSA cluster for FSxN endpoint isolation.
#------------------------------------------------------------------------------

resource "aws_subnet" "fsx_ontap" {
  count = var.create_dedicated_subnets ? length(local.dedicated_subnet_cidrs) : 0

  vpc_id            = var.vpc_id
  cidr_block        = local.dedicated_subnet_cidrs[count.index]
  availability_zone = length(var.availability_zones) > count.index ? var.availability_zones[count.index] : null

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-fsx-ontap-${count.index}"
    "rosa-gitops-layer" = "netapp-storage"
  })
}

resource "aws_route_table_association" "fsx_ontap" {
  count = var.create_dedicated_subnets ? length(aws_subnet.fsx_ontap) : 0

  subnet_id      = aws_subnet.fsx_ontap[count.index].id
  route_table_id = length(var.private_route_table_ids) > count.index ? var.private_route_table_ids[count.index] : var.private_route_table_ids[0]
}

#------------------------------------------------------------------------------
# FSx ONTAP File System
#------------------------------------------------------------------------------

resource "aws_fsx_ontap_file_system" "this" {
  storage_capacity    = var.storage_capacity_gb
  subnet_ids          = var.deployment_type == "MULTI_AZ_1" ? slice(local.effective_subnet_ids, 0, min(2, length(local.effective_subnet_ids))) : [local.preferred_subnet_id]
  preferred_subnet_id = local.preferred_subnet_id
  deployment_type     = var.deployment_type
  throughput_capacity = var.throughput_capacity_mbps
  security_group_ids  = [aws_security_group.fsx_ontap.id]

  fsx_admin_password = var.fsx_admin_password
  kms_key_id         = var.kms_key_arn

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-fsx-ontap"
    "rosa-gitops-layer" = "netapp-storage"
  })
}

#------------------------------------------------------------------------------
# Storage Virtual Machine (SVM)
#
# One SVM per filesystem. Root volume security style UNIX for NFS compatibility.
# The SVM management endpoint is used by Trident for backend configuration.
#------------------------------------------------------------------------------

resource "aws_fsx_ontap_storage_virtual_machine" "this" {
  file_system_id = aws_fsx_ontap_file_system.this.id
  name           = "${var.cluster_name}-svm"

  svm_admin_password = var.fsx_admin_password

  root_volume_security_style = "UNIX"

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-svm"
    "rosa-gitops-layer" = "netapp-storage"
  })
}

#------------------------------------------------------------------------------
# IAM Role for Trident CSI Controller (IRSA)
#
# Allows the Trident controller pod to manage FSx ONTAP volumes via the
# AWS API. Uses OIDC federation for pod-level identity.
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "trident_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${var.aws_account_id}:oidc-provider/${var.oidc_endpoint_url}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_endpoint_url}:sub"
      values = [
        "system:serviceaccount:trident:trident-controller",
        "system:serviceaccount:trident:trident-node-linux",
      ]
    }
  }
}

resource "aws_iam_role" "trident_csi" {
  name               = "${var.cluster_name}-trident-csi"
  assume_role_policy = data.aws_iam_policy_document.trident_trust.json
  path               = var.iam_role_path

  tags = merge(var.tags, {
    Name                = "${var.cluster_name}-trident-csi"
    "rosa-gitops-layer" = "netapp-storage"
    "red-hat-managed"   = "false"
  })
}

data "aws_iam_policy_document" "trident_csi" {
  statement {
    sid    = "FSxONTAPAccess"
    effect = "Allow"
    actions = [
      "fsx:DescribeFileSystems",
      "fsx:DescribeVolumes",
      "fsx:CreateVolume",
      "fsx:DeleteVolume",
      "fsx:UpdateVolume",
      "fsx:TagResource",
      "fsx:UntagResource",
      "fsx:DescribeStorageVirtualMachines",
      "fsx:DescribeBackups",
      "fsx:CreateBackup",
      "fsx:DeleteBackup",
    ]
    resources = ["*"]
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
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "trident_csi" {
  name   = "${var.cluster_name}-trident-csi-policy"
  role   = aws_iam_role.trident_csi.id
  policy = data.aws_iam_policy_document.trident_csi.json
}

#------------------------------------------------------------------------------
# Wait for IAM role propagation
#------------------------------------------------------------------------------

resource "time_sleep" "role_propagation" {
  create_duration = "10s"

  triggers = {
    role_arn = aws_iam_role.trident_csi.arn
  }

  depends_on = [aws_iam_role_policy.trident_csi]
}
