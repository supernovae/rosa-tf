#------------------------------------------------------------------------------
# BYO-VPC Subnet Helper
#
# Creates subnets, route tables, and routes inside an existing VPC for an
# additional ROSA cluster. This is a standalone helper -- NOT wired into
# any environment module. Run it manually, then copy the output subnet IDs
# into your cluster's BYO-VPC tfvars.
#
# Usage:
#   cd helpers/byo-vpc-subnets
#   terraform init
#   terraform apply -var-file=examples/lab.tfvars
#   # Copy output subnet IDs into your cluster tfvars
#
# Egress modes:
#   - "nat" (default): Reuses the parent VPC's existing NAT gateway
#   - "tgw": Routes via Transit Gateway (GovCloud / hub-spoke)
#------------------------------------------------------------------------------

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Look up existing infrastructure in the parent VPC
#------------------------------------------------------------------------------

# NAT gateways (for NAT mode -- reuse the parent VPC's NAT)
# Multi-AZ VPCs have multiple NATs; we just need any one of them
data "aws_nat_gateways" "existing" {
  count  = var.egress_type == "nat" ? 1 : 0
  vpc_id = var.vpc_id

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_nat_gateway" "selected" {
  count = var.egress_type == "nat" ? 1 : 0
  id    = data.aws_nat_gateways.existing[0].ids[0]
}

# S3 VPC endpoint (add our new route tables to it)
data "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${data.aws_region.current.id}.s3"
}

#------------------------------------------------------------------------------
# Private Subnets
#------------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name                              = "${var.cluster_name}-private-${var.availability_zones[count.index]}"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

#------------------------------------------------------------------------------
# Public Subnets (optional -- for public clusters)
#------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = var.create_public_subnets ? length(var.availability_zones) : 0

  vpc_id                  = var.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name                     = "${var.cluster_name}-public-${var.availability_zones[count.index]}"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

#------------------------------------------------------------------------------
# Private Route Tables
#------------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-private-rt-${var.availability_zones[count.index]}"
    }
  )
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------
# Private Routes -- NAT Gateway (reuses parent VPC's NAT)
#------------------------------------------------------------------------------

resource "aws_route" "private_nat" {
  count = var.egress_type == "nat" ? length(var.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = data.aws_nat_gateway.selected[0].id
}

#------------------------------------------------------------------------------
# Private Routes -- Transit Gateway
#------------------------------------------------------------------------------

resource "aws_route" "private_tgw" {
  count = var.egress_type == "tgw" ? length(var.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = var.transit_gateway_route_cidr
  transit_gateway_id     = var.transit_gateway_id
}

#------------------------------------------------------------------------------
# S3 VPC Endpoint -- associate new route tables with existing endpoint
#------------------------------------------------------------------------------

resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  count = length(var.availability_zones)

  route_table_id  = aws_route_table.private[count.index].id
  vpc_endpoint_id = data.aws_vpc_endpoint.s3.id
}

#------------------------------------------------------------------------------
# Validations
#------------------------------------------------------------------------------

resource "terraform_data" "validate_tgw" {
  count = var.egress_type == "tgw" ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.transit_gateway_id != null
      error_message = "transit_gateway_id is required when egress_type = \"tgw\"."
    }
  }
}

resource "terraform_data" "validate_public_subnets" {
  count = var.create_public_subnets ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
      error_message = "public_subnet_cidrs must have the same count as availability_zones."
    }
  }
}
