# FSx for ONTAP infrastructure. Trident uses the SVM REST endpoint, not AWS APIs;
# no IAM role or wildcard FSx/KMS permissions are needed by the CSI pods.
data "aws_subnet" "clients" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}
locals {
  multi_az               = startswith(var.deployment_type, "MULTI_AZ")
  second_generation      = endswith(var.deployment_type, "_2")
  effective_subnet_ids   = var.create_dedicated_subnets ? aws_subnet.fsx_ontap[*].id : var.private_subnet_ids
  preferred_subnet_id    = try(local.effective_subnet_ids[0], null)
  client_cidrs           = length(var.netapp_fsx_config.client_cidrs) > 0 ? var.netapp_fsx_config.client_cidrs : distinct(data.aws_subnet.clients[*].cidr_block)
  client_route_table_ids = length(var.netapp_fsx_config.client_route_table_ids) > 0 ? var.netapp_fsx_config.client_route_table_ids : var.private_route_table_ids
}
resource "aws_security_group" "fsx_ontap" {
  name_prefix = "${var.cluster_name}-fsx-ontap-"
  description = "FSx ONTAP access from approved ROSA worker networks"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_name}-fsx-ontap", "rosa-gitops-layer" = "netapp-storage" })
  lifecycle { create_before_destroy = true }
}
resource "aws_security_group_rule" "fsx_ontap_mgmt" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = local.client_cidrs
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "ONTAP REST management from approved workers"
}
resource "aws_security_group_rule" "fsx_nfs_tcp" {
  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = local.client_cidrs
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "NFSv4.1 TCP from approved workers"
}
resource "aws_security_group_rule" "fsx_iscsi" {
  type              = "ingress"
  from_port         = 3260
  to_port           = 3260
  protocol          = "tcp"
  cidr_blocks       = local.client_cidrs
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "iSCSI target portals from approved workers"
}
resource "aws_security_group_rule" "fsx_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.fsx_ontap.id
  description       = "VPC-only egress; external directory/replication paths need separate review"
}
resource "aws_subnet" "fsx_ontap" {
  count             = var.create_dedicated_subnets ? length(var.dedicated_subnet_cidrs) : 0
  vpc_id            = var.vpc_id
  cidr_block        = var.dedicated_subnet_cidrs[count.index]
  availability_zone = try(var.availability_zones[count.index], null)
  tags              = merge(var.tags, { Name = "${var.cluster_name}-fsx-ontap-${count.index}", "rosa-gitops-layer" = "netapp-storage" })
}
resource "aws_route_table_association" "fsx_ontap" {
  count          = var.create_dedicated_subnets ? length(aws_subnet.fsx_ontap) : 0
  subnet_id      = aws_subnet.fsx_ontap[count.index].id
  route_table_id = try(local.client_route_table_ids[count.index], local.client_route_table_ids[0])
}
resource "aws_fsx_ontap_file_system" "this" {
  storage_capacity                = var.storage_capacity_gb
  subnet_ids                      = local.multi_az ? slice(local.effective_subnet_ids, 0, min(2, length(local.effective_subnet_ids))) : compact([local.preferred_subnet_id])
  preferred_subnet_id             = local.preferred_subnet_id
  deployment_type                 = var.deployment_type
  throughput_capacity             = local.second_generation ? null : var.throughput_capacity_mbps
  throughput_capacity_per_ha_pair = local.second_generation ? var.throughput_capacity_mbps : null
  # One HA pair supports shared NFS and SAN workloads; scale-out is a separate design.
  ha_pairs                          = local.second_generation ? 1 : null
  route_table_ids                   = local.multi_az ? local.client_route_table_ids : null
  security_group_ids                = [aws_security_group.fsx_ontap.id]
  fsx_admin_password                = var.fsx_admin_password
  kms_key_id                        = var.kms_key_arn
  automatic_backup_retention_days   = var.netapp_fsx_config.automatic_backup_retention_days
  daily_automatic_backup_start_time = var.netapp_fsx_config.daily_backup_start_time
  weekly_maintenance_start_time     = var.netapp_fsx_config.weekly_maintenance_start_time
  disk_iops_configuration {
    mode = var.netapp_fsx_config.provisioned_iops == null ? "AUTOMATIC" : "USER_PROVISIONED"
    iops = var.netapp_fsx_config.provisioned_iops
  }
  tags = merge(var.tags, { Name = "${var.cluster_name}-fsx-ontap", "rosa-gitops-layer" = "netapp-storage" })
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.fsx_svm_password != null && var.fsx_svm_password != var.fsx_admin_password
      error_message = "Provide an independent fsx_svm_password; do not reuse the filesystem administrator password for CSI backend access."
    }
    precondition {
      condition     = length(local.effective_subnet_ids) >= (local.multi_az ? 2 : 1)
      error_message = "FSx needs one Single-AZ subnet or two Multi-AZ subnets in distinct AZs."
    }
    precondition {
      condition     = !local.multi_az || length(local.client_route_table_ids) > 0
      error_message = "Multi-AZ requires all client route tables, including explicit IDs for BYO-VPC."
    }
    precondition {
      condition     = !var.create_dedicated_subnets || (length(var.dedicated_subnet_cidrs) == (local.multi_az ? 2 : 1) && length(var.availability_zones) >= length(var.dedicated_subnet_cidrs) && length(local.client_route_table_ids) > 0)
      error_message = "Dedicated subnets require explicit non-overlapping CIDRs, AZs and route tables; automatic CIDR guessing is not safe."
    }
    precondition {
      condition     = var.netapp_fsx_config.provisioned_iops == null ? true : (var.netapp_fsx_config.provisioned_iops >= 3 * var.storage_capacity_gb && floor(var.netapp_fsx_config.provisioned_iops) == var.netapp_fsx_config.provisioned_iops)
      error_message = "Provisioned SSD IOPS must be an integer at least 3 per GiB; verify generation-specific service maxima."
    }
  }
}
resource "aws_fsx_ontap_storage_virtual_machine" "this" {
  file_system_id             = aws_fsx_ontap_file_system.this.id
  name                       = "${var.cluster_name}-svm"
  svm_admin_password         = var.fsx_svm_password
  root_volume_security_style = "UNIX"
  tags                       = merge(var.tags, { Name = "${var.cluster_name}-svm", "rosa-gitops-layer" = "netapp-storage" })
  lifecycle { prevent_destroy = true }
}
