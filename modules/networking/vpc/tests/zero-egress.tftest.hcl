# No AWS API calls; verify the isolated network plan in the GovCloud partition.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-gov-west-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws-us-gov" }
  }
}

variables {
  cluster_name         = "gov-zero-test"
  availability_zones   = ["us-gov-west-1a"]
  private_subnet_cidrs = ["10.0.0.0/20"]
  public_subnet_cidrs  = ["10.0.48.0/20"]
}

run "isolated_endpoints" {
  command = plan
  variables {
    egress_type                 = "none"
    interface_endpoint_services = ["ec2", "sts", "kms", "ecr.api", "ecr.dkr"]
  }
  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "Zero-egress VPCs must deny all traffic through the default security group."
  }
  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_nat_gateway.this) == 0 && length(aws_subnet.public) == 0 && length(aws_route.private_tgw) == 0
    error_message = "Zero-egress must not create public subnets, NAT, IGW or TGW egress."
  }
  assert {
    condition     = length(aws_vpc_endpoint.interface) == 5 && alltrue([for endpoint in aws_vpc_endpoint.interface : endpoint.private_dns_enabled && startswith(endpoint.service_name, "com.amazonaws.us-gov-west-1.")])
    error_message = "Required GovCloud APIs must have private-DNS interface endpoints."
  }
  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && aws_vpc_security_group_ingress_rule.interface_endpoints_https[0].cidr_ipv4 == "10.0.0.0/16" && aws_vpc_security_group_ingress_rule.interface_endpoints_https[0].from_port == 443
    error_message = "Retain the S3 gateway and restrict endpoint ingress to VPC HTTPS."
  }
}

run "existing_nat_default" {
  command = plan
  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "NAT VPCs must also deny all traffic through the default security group."
  }
  assert {
    condition     = length(aws_internet_gateway.this) == 1 && length(aws_nat_gateway.this) == 1 && length(aws_vpc_endpoint.interface) == 0
    error_message = "Other environment callers must retain existing NAT defaults without new endpoints."
  }
}
