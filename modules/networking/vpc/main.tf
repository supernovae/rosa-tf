#------------------------------------------------------------------------------
# VPC Module for ROSA
#
# Supports four egress modes:
# 1. NAT Gateway Mode (egress_type = "nat"):
#    - Creates public subnets, Internet Gateway, and NAT gateways
#    - Standalone deployment with no external dependencies
#    - Higher cost due to NAT gateway charges
#
# 2. Transit Gateway Mode (egress_type = "tgw"):
#    - Private subnets only, no public infrastructure
#    - Requires existing Transit Gateway with internet access
#    - Lower cost, centralized egress management
#
# 3. Proxy Mode (egress_type = "proxy"):
#    - Private subnets only, no public infrastructure
#    - Egress via HTTP/HTTPS proxy configured in cluster
#    - Requires proxy infrastructure to be configured separately
#
# 4. None Mode (egress_type = "none"):
#    - Private subnets only, no public infrastructure, no egress
#    - For zero-egress/air-gapped clusters (ROSA HCP only)
#    - Cluster pulls OCP images from Red Hat's regional ECR
#    - Custom operators must be mirrored to your own ECR
#    - See docs/ZERO-EGRESS.md for setup instructions
#
# EXTERNAL INGRESS (if needed with tgw/proxy/none mode):
# To expose services to the internet, you would need to add:
# 1. Public subnets with tags: "kubernetes.io/role/elb" = "1"
# 2. Internet Gateway attached to the VPC
# 3. Route table with 0.0.0.0/0 -> IGW
# See README.md for details.
#------------------------------------------------------------------------------

locals {
  create_nat_infrastructure = var.egress_type == "nat"
  create_tgw_routes         = var.egress_type == "tgw" && var.transit_gateway_id != null

  # NAT gateway count: 1 for single NAT mode, otherwise one per AZ
  nat_gateway_count = local.create_nat_infrastructure ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0
}

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------

# trivy:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs -- Flow logs are optional (enable_flow_logs variable)
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Explicitly disable IPv6 - ROSA HCP does not support IPv6
  assign_generated_ipv6_cidr_block = false

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpc"
    }
  )
}

#------------------------------------------------------------------------------
# Internet Gateway (NAT mode only)
#------------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count = local.create_nat_infrastructure ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-igw"
    }
  )
}

#------------------------------------------------------------------------------
# Public Subnets (NAT mode only)
#------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = local.create_nat_infrastructure ? length(var.availability_zones) : 0

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false # Security best practice

  # Explicitly disable IPv6 - ROSA HCP does not support IPv6
  assign_ipv6_address_on_creation = false

  # Note: kubernetes.io/role/elb tag enables the cloud controller / AWS load balancer
  # controller to discover this subnet for internet-facing NLBs.
  # ROSA receives explicit subnet IDs (not tag-based discovery), so no exclusion
  # tag is needed. Do NOT add kubernetes.io/cluster/unmanaged here -- it causes the
  # cloud controller to filter out this subnet when creating NLBs for custom
  # IngressControllers.
  tags = merge(
    var.tags,
    {
      Name                     = "${var.cluster_name}-public-${var.availability_zones[count.index]}"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

#------------------------------------------------------------------------------
# Private Subnets (all modes)
#------------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  # Explicitly disable IPv6 - ROSA HCP does not support IPv6
  assign_ipv6_address_on_creation = false

  # Note: kubernetes.io/role/internal-elb tag enables AWS load balancer controller to discover this subnet
  # Note: kubernetes.io/cluster/<cluster-id> tag is managed by ROSA installer, not Terraform
  tags = merge(
    var.tags,
    {
      Name                              = "${var.cluster_name}-private-${var.availability_zones[count.index]}"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

#------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways (NAT mode only)
# Count depends on single_nat_gateway setting
#------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nat-eip-${var.availability_zones[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

#------------------------------------------------------------------------------
# NAT Gateways (NAT mode only)
# - Multi-AZ (single_nat_gateway=false): One per AZ for high availability
# - Single NAT (single_nat_gateway=true): One in first AZ for cost savings
#------------------------------------------------------------------------------

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nat-${var.availability_zones[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]

  # NAT Gateway deletion can take several minutes
  timeouts {
    create = "10m"
    delete = "10m"
  }
}

#------------------------------------------------------------------------------
# Public Route Table (NAT mode only)
#------------------------------------------------------------------------------

resource "aws_route_table" "public" {
  count = local.create_nat_infrastructure ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-public-rt"
    }
  )
}

resource "aws_route" "public_internet" {
  count = local.create_nat_infrastructure ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count = local.create_nat_infrastructure ? length(var.availability_zones) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

#------------------------------------------------------------------------------
# Private Route Tables (all modes)
#------------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

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
# Private Routes - NAT Gateway (NAT mode)
# When single_nat_gateway=true, all routes point to the single NAT
#------------------------------------------------------------------------------

resource "aws_route" "private_nat" {
  count = local.create_nat_infrastructure ? length(var.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # Use same NAT for all AZs when single_nat_gateway is true
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

#------------------------------------------------------------------------------
# Private Routes - Transit Gateway (TGW mode)
#------------------------------------------------------------------------------

resource "aws_route" "private_tgw" {
  count = local.create_tgw_routes ? length(var.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = var.transit_gateway_route_cidr
  transit_gateway_id     = var.transit_gateway_id
}

#------------------------------------------------------------------------------
# VPC Endpoints
#
# Only S3 Gateway endpoint is managed here for NAT cost savings.
#------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.private[*].id,
    local.create_nat_infrastructure ? [aws_route_table.public[0].id] : []
  )

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-s3-endpoint"
    }
  )

  timeouts {
    create = "10m"
    delete = "10m"
  }
}

#------------------------------------------------------------------------------
# VPC Flow Logs (Optional)
# Captures network traffic metadata for security and troubleshooting
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.cluster_name}-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.infrastructure_kms_key_arn

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpc-flow-logs"
    }
  )
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.cluster_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.cluster_name}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpc-flow-log"
    }
  )
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_region" "current" {}
