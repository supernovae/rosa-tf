#------------------------------------------------------------------------------
# BYO-VPC Subnet Helper Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID (pass-through for convenience)."
  value       = var.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the created private subnets. Copy into existing_private_subnet_ids."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the created public subnets (empty if not created). Copy into existing_public_subnet_ids."
  value       = aws_subnet.public[*].id
}

output "availability_zones" {
  description = "Availability zones of the created subnets."
  value       = var.availability_zones
}

output "private_route_table_ids" {
  description = "IDs of the created private route tables."
  value       = aws_route_table.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the created private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the created public subnets (empty if not created)."
  value       = aws_subnet.public[*].cidr_block
}

output "egress_type" {
  description = "Egress mode used for these subnets."
  value       = var.egress_type
}

output "nat_gateway_id" {
  description = "NAT gateway ID being reused (null if TGW mode)."
  value       = var.egress_type == "nat" ? data.aws_nat_gateway.selected[0].id : null
}

#------------------------------------------------------------------------------
# Ready-to-paste tfvars snippet
#------------------------------------------------------------------------------

output "usage_instructions" {
  description = "Copy-paste snippet for your cluster's BYO-VPC tfvars."
  value       = <<-EOT

    ============================================================================
    BYO-VPC subnets created for: ${var.cluster_name}
    ============================================================================

    Add the following to your cluster tfvars file:

    existing_vpc_id             = "${var.vpc_id}"
    existing_private_subnet_ids = ${jsonencode(aws_subnet.private[*].id)}
    ${length(aws_subnet.public) > 0 ? "existing_public_subnet_ids  = ${jsonencode(aws_subnet.public[*].id)}" : "# existing_public_subnet_ids  = []  # No public subnets created"}

    # Non-overlapping CIDRs (see docs/BYO-VPC.md for planning guide)
    pod_cidr     = "10.132.0.0/14"   # <-- Adjust to avoid conflicts
    service_cidr = "172.31.0.0/16"   # <-- Adjust to avoid conflicts

    ============================================================================
  EOT
}
