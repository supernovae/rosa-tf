#------------------------------------------------------------------------------
# VPC Module Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (empty if egress_type != 'nat')."
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets (empty if egress_type != 'nat')."
  value       = aws_subnet.public[*].cidr_block
}

output "availability_zones" {
  description = "Availability zones of the subnets."
  value       = var.availability_zones
}

output "private_route_table_ids" {
  description = "IDs of the private route tables."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table (null if egress_type != 'nat')."
  value       = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways (empty if egress_type != 'nat')."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_ips" {
  description = "Elastic IP addresses of NAT gateways (empty if egress_type != 'nat')."
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway (null if egress_type != 'nat')."
  value       = length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
}

output "s3_endpoint_id" {
  description = "ID of the S3 VPC endpoint."
  value       = aws_vpc_endpoint.s3.id
}

output "egress_type" {
  description = "The egress type configured for this VPC (nat, tgw, proxy, or none)."
  value       = var.egress_type
}

output "topology" {
  description = "VPC topology summary."
  value = {
    az_count           = length(var.availability_zones)
    single_nat_gateway = var.single_nat_gateway
    nat_gateway_count  = local.nat_gateway_count
    egress_type        = var.egress_type
  }
}

output "flow_logs_enabled" {
  description = "Whether VPC flow logs are enabled."
  value       = var.enable_flow_logs
}

output "flow_logs_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC flow logs (null if disabled)."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].arn : null
}
