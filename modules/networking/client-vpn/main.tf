#------------------------------------------------------------------------------
# AWS Client VPN Module for ROSA Classic GovCloud
#
# This module creates an AWS Client VPN endpoint for secure access to the
# private VPC hosting the ROSA cluster. This is an ALTERNATIVE to SSM-based
# access and provides:
#
# - Direct network connectivity to the VPC
# - VPC DNS resolution for cluster endpoints
# - No port forwarding or tunneling required
# - Native access to cluster API and console
#
# AUTHENTICATION:
# Uses mutual TLS (certificate-based) authentication. The module generates
# self-signed certificates for the server and client.
#
# USAGE:
# After terraform apply, use the generated .ovpn file with any OpenVPN client.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

#------------------------------------------------------------------------------
# TLS Certificates for Mutual Authentication
#------------------------------------------------------------------------------

# CA Private Key
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# CA Certificate
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.cluster_name}-vpn-ca"
    organization = var.certificate_organization
  }

  validity_period_hours = var.certificate_validity_days * 24
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Server Private Key
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Server Certificate Request
# NOTE: AWS Client VPN requires a domain name in the certificate's SAN
resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "server.${var.cluster_name}.vpn.internal"
    organization = var.certificate_organization
  }

  # AWS Client VPN requires DNS names in the certificate
  dns_names = [
    "server.${var.cluster_name}.vpn.internal",
    "${var.cluster_name}-vpn-server",
  ]
}

# Server Certificate (signed by CA)
resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.certificate_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Client Private Key
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Client Certificate Request
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${var.cluster_name}-vpn-client"
    organization = var.certificate_organization
  }
}

# Client Certificate (signed by CA)
resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.certificate_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

#------------------------------------------------------------------------------
# Import Certificates to ACM
#------------------------------------------------------------------------------

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpn-server-cert"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "client" {
  private_key       = tls_private_key.client.private_key_pem
  certificate_body  = tls_locally_signed_cert.client.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpn-client-cert"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Group for VPN Connection Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/${var.cluster_name}-client-vpn"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpn-logs"
    }
  )
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connection-logs"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

#------------------------------------------------------------------------------
# Security Group for VPN Endpoint
#------------------------------------------------------------------------------

resource "aws_security_group" "vpn" {
  name        = "${var.cluster_name}-client-vpn"
  description = "Security group for Client VPN endpoint"
  vpc_id      = var.vpc_id

  # Allow all traffic from VPN clients to VPC
  ingress {
    description = "All traffic from VPN clients"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.client_cidr_block]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-client-vpn-sg"
    }
  )
}

#------------------------------------------------------------------------------
# Client VPN Endpoint
#------------------------------------------------------------------------------

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "Client VPN for ${var.cluster_name} ROSA cluster access"
  server_certificate_arn = aws_acm_certificate.server.arn
  client_cidr_block      = var.client_cidr_block

  # Mutual TLS authentication
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.client.arn
  }

  # Connection logging
  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  # Use VPC DNS for cluster endpoint resolution
  dns_servers = var.dns_servers != null ? var.dns_servers : null

  # Split tunnel - only VPC traffic goes through VPN
  split_tunnel = var.split_tunnel

  # Transport protocol
  transport_protocol = "udp"
  vpn_port           = 443

  # Security group
  security_group_ids = [aws_security_group.vpn.id]
  vpc_id             = var.vpc_id

  # Session timeout
  session_timeout_hours = var.session_timeout_hours

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-client-vpn"
    }
  )

  # Note: aws_ec2_client_vpn_endpoint doesn't support custom timeouts
  # The slow operations are primarily in network associations (below)
}

#------------------------------------------------------------------------------
# VPN Network Associations (attach to subnets)
#------------------------------------------------------------------------------

resource "aws_ec2_client_vpn_network_association" "this" {
  count = length(var.subnet_ids)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_ids[count.index]

  # AWS Client VPN associations are SLOW - 10-20 minutes is normal
  timeouts {
    create = "30m"
    delete = "30m"
  }
}

#------------------------------------------------------------------------------
# Authorization Rules
#------------------------------------------------------------------------------

# Allow access to the entire VPC
resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow access to VPC CIDR"

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

# Allow access to cluster service CIDR if provided
resource "aws_ec2_client_vpn_authorization_rule" "service_cidr" {
  count = var.service_cidr != null ? 1 : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.service_cidr
  authorize_all_groups   = true
  description            = "Allow access to cluster service CIDR"

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

#------------------------------------------------------------------------------
# Generate OpenVPN Client Configuration File
#------------------------------------------------------------------------------

resource "local_file" "client_config" {
  filename = "${path.root}/output/${var.cluster_name}-vpn-client.ovpn"
  content  = <<-EOT
# OpenVPN Client Configuration for ${var.cluster_name}
# Generated by Terraform - AWS Client VPN
#
# USAGE:
#   1. Install OpenVPN client (or AWS VPN Client)
#   2. Import this .ovpn file
#   3. Connect to the VPN
#   4. Access cluster endpoints directly:
#      - API: https://api.${var.cluster_domain}:6443
#      - Console: https://console-openshift-console.apps.${var.cluster_domain}
#
# CERTIFICATE VALIDITY: ${var.certificate_validity_days} days
# Generated: ${timestamp()}

client
dev tun
proto udp
remote ${replace(aws_ec2_client_vpn_endpoint.this.dns_name, "*.", "")} 443
remote-random-hostname
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-GCM
verb 3

<ca>
${tls_self_signed_cert.ca.cert_pem}
</ca>

<cert>
${tls_locally_signed_cert.client.cert_pem}
</cert>

<key>
${tls_private_key.client.private_key_pem}
</key>

reneg-sec 0
EOT

  file_permission = "0600"

  depends_on = [aws_ec2_client_vpn_endpoint.this]
}

#------------------------------------------------------------------------------
# Output certificates for backup/rotation
#------------------------------------------------------------------------------

resource "local_file" "ca_cert" {
  filename        = "${path.root}/output/${var.cluster_name}-vpn-ca.crt"
  content         = tls_self_signed_cert.ca.cert_pem
  file_permission = "0600"
}

resource "local_file" "client_cert" {
  filename        = "${path.root}/output/${var.cluster_name}-vpn-client.crt"
  content         = tls_locally_signed_cert.client.cert_pem
  file_permission = "0600"
}

resource "local_sensitive_file" "client_key" {
  filename        = "${path.root}/output/${var.cluster_name}-vpn-client.key"
  content         = tls_private_key.client.private_key_pem
  file_permission = "0600"
}
