#------------------------------------------------------------------------------
# Client VPN Module Outputs
#------------------------------------------------------------------------------

output "vpn_endpoint_id" {
  description = "ID of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.this.id
}

output "vpn_endpoint_dns" {
  description = "DNS name of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.this.dns_name
}

output "vpn_endpoint_arn" {
  description = "ARN of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.this.arn
}

output "client_config_path" {
  description = "Path to the generated OpenVPN client configuration file."
  value       = local_file.client_config.filename
}

output "security_group_id" {
  description = "ID of the VPN security group."
  value       = aws_security_group.vpn.id
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for VPN logs."
  value       = aws_cloudwatch_log_group.vpn.name
}

output "certificate_expiry" {
  description = "Expiry date of the client certificate."
  value       = tls_locally_signed_cert.client.validity_end_time
}

output "connection_instructions" {
  description = "Instructions for connecting to the VPN."
  value       = <<-EOT

================================================================================
AWS Client VPN Connection Instructions
================================================================================

1. INSTALL VPN CLIENT
   
   Option A - AWS VPN Client (recommended):
   Download from: https://aws.amazon.com/vpn/client-vpn-download/
   
   Option B - OpenVPN Client:
   macOS:    brew install openvpn
   Linux:    sudo apt install openvpn
   Windows:  https://openvpn.net/community-downloads/

2. IMPORT CONFIGURATION
   
   Configuration file: ${local_file.client_config.filename}
   
   AWS VPN Client:
   - File > Manage Profiles > Add Profile
   - Browse to the .ovpn file
   
   OpenVPN CLI:
   sudo openvpn --config ${local_file.client_config.filename}

3. CONNECT TO VPN
   
   After connecting, you can directly access:
   - Cluster API: https://api.${var.cluster_domain}:6443
   - Web Console: https://console-openshift-console.apps.${var.cluster_domain}

4. VERIFY CONNECTION
   
   # Check VPN connection
   ping ${cidrhost(var.vpc_cidr, 1)}
   
   # Test DNS resolution
   nslookup api.${var.cluster_domain}
   
   # Test cluster API
   curl -k https://api.${var.cluster_domain}:6443/healthz

================================================================================
Certificate expires: ${tls_locally_signed_cert.client.validity_end_time}
================================================================================
EOT
}
