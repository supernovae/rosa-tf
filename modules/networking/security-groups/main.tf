#------------------------------------------------------------------------------
# Additional Security Groups Module
#
# Creates or aggregates security groups for ROSA clusters.
#
# IMPORTANT: Security groups can only be attached at cluster creation time.
# They cannot be modified after the cluster is deployed.
#
# Supports:
# - ROSA HCP: Compute security groups only (control plane is Red Hat managed)
# - ROSA Classic: Compute, control plane, and infrastructure security groups
#------------------------------------------------------------------------------

locals {
  # Determine if we should create any security groups
  create_compute_sg       = var.enabled && (length(var.compute_ingress_rules) > 0 || length(var.compute_egress_rules) > 0 || var.use_intra_vpc_template)
  create_control_plane_sg = var.enabled && var.cluster_type == "classic" && (length(var.control_plane_ingress_rules) > 0 || length(var.control_plane_egress_rules) > 0 || var.use_intra_vpc_template)
  create_infra_sg         = var.enabled && var.cluster_type == "classic" && (length(var.infra_ingress_rules) > 0 || length(var.infra_egress_rules) > 0 || var.use_intra_vpc_template)

  # Combine existing and created security group IDs
  compute_security_group_ids = var.enabled ? concat(
    var.existing_compute_security_group_ids,
    local.create_compute_sg ? [aws_security_group.compute[0].id] : []
  ) : []

  control_plane_security_group_ids = var.enabled && var.cluster_type == "classic" ? concat(
    var.existing_control_plane_security_group_ids,
    local.create_control_plane_sg ? [aws_security_group.control_plane[0].id] : []
  ) : []

  infra_security_group_ids = var.enabled && var.cluster_type == "classic" ? concat(
    var.existing_infra_security_group_ids,
    local.create_infra_sg ? [aws_security_group.infra[0].id] : []
  ) : []

  # Common tags for all security groups
  # Note: kubernetes.io/cluster/<cluster-id> and red-hat-* tags are managed by ROSA installer
  # We only add our own identifying tags that don't conflict with Red Hat's managed tags
  common_tags = merge(
    var.tags,
    {
      "rosa-tf/cluster-name" = var.cluster_name
    }
  )
}

#------------------------------------------------------------------------------
# Compute/Worker Security Group
#------------------------------------------------------------------------------

resource "aws_security_group" "compute" {
  count = local.create_compute_sg ? 1 : 0

  name        = "${var.cluster_name}-additional-compute-sg"
  description = "Additional security group for ROSA ${var.cluster_name} compute/worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-additional-compute-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Intra-VPC template rules for compute
resource "aws_security_group_rule" "compute_intra_vpc_tcp" {
  count = local.create_compute_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.compute[0].id
  type              = "ingress"
  description       = "Allow all TCP from VPC CIDR (intra-VPC template)"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "compute_intra_vpc_udp" {
  count = local.create_compute_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.compute[0].id
  type              = "ingress"
  description       = "Allow all UDP from VPC CIDR (intra-VPC template)"
  from_port         = 0
  to_port           = 65535
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "compute_intra_vpc_icmp" {
  count = local.create_compute_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.compute[0].id
  type              = "ingress"
  description       = "Allow all ICMP from VPC CIDR (intra-VPC template)"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = [var.vpc_cidr]
}

# Custom ingress rules for compute
resource "aws_security_group_rule" "compute_ingress" {
  for_each = { for idx, rule in var.compute_ingress_rules : idx => rule }

  security_group_id = aws_security_group.compute[0].id
  type              = "ingress"
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  # Note: source_security_group_id only accepts a single SG, so we create separate rules
  self = each.value.self
}

# Custom egress rules for compute
resource "aws_security_group_rule" "compute_egress" {
  for_each = { for idx, rule in var.compute_egress_rules : idx => rule }

  security_group_id = aws_security_group.compute[0].id
  type              = "egress"
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  self              = each.value.self
}

#------------------------------------------------------------------------------
# Control Plane Security Group (Classic only)
#------------------------------------------------------------------------------

resource "aws_security_group" "control_plane" {
  count = local.create_control_plane_sg ? 1 : 0

  name        = "${var.cluster_name}-additional-cp-sg"
  description = "Additional security group for ROSA ${var.cluster_name} control plane nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-additional-cp-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Intra-VPC template rules for control plane
resource "aws_security_group_rule" "control_plane_intra_vpc_tcp" {
  count = local.create_control_plane_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.control_plane[0].id
  type              = "ingress"
  description       = "Allow all TCP from VPC CIDR (intra-VPC template)"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "control_plane_intra_vpc_udp" {
  count = local.create_control_plane_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.control_plane[0].id
  type              = "ingress"
  description       = "Allow all UDP from VPC CIDR (intra-VPC template)"
  from_port         = 0
  to_port           = 65535
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "control_plane_intra_vpc_icmp" {
  count = local.create_control_plane_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.control_plane[0].id
  type              = "ingress"
  description       = "Allow all ICMP from VPC CIDR (intra-VPC template)"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = [var.vpc_cidr]
}

# Custom ingress rules for control plane
resource "aws_security_group_rule" "control_plane_ingress" {
  for_each = { for idx, rule in var.control_plane_ingress_rules : idx => rule }

  security_group_id = aws_security_group.control_plane[0].id
  type              = "ingress"
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  self              = each.value.self
}

# Custom egress rules for control plane
resource "aws_security_group_rule" "control_plane_egress" {
  for_each = { for idx, rule in var.control_plane_egress_rules : idx => rule }

  security_group_id = aws_security_group.control_plane[0].id
  type              = "egress"
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  self              = each.value.self
}

#------------------------------------------------------------------------------
# Infrastructure Security Group (Classic only)
#------------------------------------------------------------------------------

resource "aws_security_group" "infra" {
  count = local.create_infra_sg ? 1 : 0

  name        = "${var.cluster_name}-additional-infra-sg"
  description = "Additional security group for ROSA ${var.cluster_name} infrastructure nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-additional-infra-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Intra-VPC template rules for infra
resource "aws_security_group_rule" "infra_intra_vpc_tcp" {
  count = local.create_infra_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.infra[0].id
  type              = "ingress"
  description       = "Allow all TCP from VPC CIDR (intra-VPC template)"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "infra_intra_vpc_udp" {
  count = local.create_infra_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.infra[0].id
  type              = "ingress"
  description       = "Allow all UDP from VPC CIDR (intra-VPC template)"
  from_port         = 0
  to_port           = 65535
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "infra_intra_vpc_icmp" {
  count = local.create_infra_sg && var.use_intra_vpc_template ? 1 : 0

  security_group_id = aws_security_group.infra[0].id
  type              = "ingress"
  description       = "Allow all ICMP from VPC CIDR (intra-VPC template)"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = [var.vpc_cidr]
}

# Custom ingress rules for infra
resource "aws_security_group_rule" "infra_ingress" {
  for_each = { for idx, rule in var.infra_ingress_rules : idx => rule }

  security_group_id = aws_security_group.infra[0].id
  type              = "ingress"
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  self              = each.value.self
}

# Custom egress rules for infra
resource "aws_security_group_rule" "infra_egress" {
  for_each = { for idx, rule in var.infra_egress_rules : idx => rule }

  security_group_id = aws_security_group.infra[0].id
  type              = "egress"
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  self              = each.value.self
}
