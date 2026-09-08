# Private API access for isolated worker subnets. S3 is managed in main.tf.
resource "aws_security_group" "interface_endpoints" {
  count       = length(var.interface_endpoint_services) > 0 ? 1 : 0
  name_prefix = "${var.cluster_name}-vpce-"
  description = "HTTPS to private AWS API endpoints from the cluster VPC"
  vpc_id      = aws_vpc.this.id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "interface_endpoints_https" {
  count             = length(var.interface_endpoint_services) > 0 ? 1 : 0
  security_group_id = aws_security_group.interface_endpoints[0].id
  description       = "Private AWS API access from VPC clients"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = var.interface_endpoint_services
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.interface_endpoints[0].id]
  tags                = merge(var.tags, { Name = "${var.cluster_name}-${each.key}" })
  depends_on          = [aws_vpc_security_group_ingress_rule.interface_endpoints_https]
}
