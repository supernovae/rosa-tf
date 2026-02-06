#------------------------------------------------------------------------------
# Jump Host Module Outputs
#------------------------------------------------------------------------------

output "instance_id" {
  description = "Instance ID of the jump host (use for SSM sessions)."
  value       = aws_instance.jumphost.id
}

output "private_ip" {
  description = "Private IP address of the jump host."
  value       = aws_instance.jumphost.private_ip
}

output "security_group_id" {
  description = "Security group ID of the jump host."
  value       = aws_security_group.jumphost.id
}

output "iam_role_arn" {
  description = "ARN of the jump host IAM role."
  value       = aws_iam_role.jumphost.arn
}

output "iam_instance_profile_name" {
  description = "Name of the instance profile."
  value       = aws_iam_instance_profile.jumphost.name
}

output "ssm_session_command" {
  description = "AWS CLI command to start an SSM session to the jump host."
  value       = "aws ssm start-session --target ${aws_instance.jumphost.id} --region ${data.aws_region.current.id}"
}

output "ssm_access_instructions" {
  description = "Instructions for accessing cluster via SSM jumphost."
  value       = <<-EOT
    ================================================================================
    SSM ACCESS FOR ROSA CLUSTER
    ================================================================================
    
    PREREQUISITES:
    Install Session Manager Plugin:
      - macOS: brew install --cask session-manager-plugin
      - Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
      - Windows: Download MSI from AWS docs
    
    CLI ACCESS VIA JUMPHOST
    -----------------------
    Connect to the jumphost and use oc/kubectl directly from there.
    The jumphost is inside the VPC and can access all cluster endpoints.
    
    # Start SSM session to jumphost:
    aws ssm start-session --target ${aws_instance.jumphost.id} --region ${data.aws_region.current.id}
    
    # Once connected, login to the cluster:
    oc login https://api.${var.cluster_domain}:6443 -u cluster-admin
    
    # Get admin password (run on your local machine):
    terraform output -raw cluster_admin_password
    
    WEB CONSOLE & WORKSTATION ACCESS
    --------------------------------
    For web console access or local workstation API access, configure:
      - AWS Client VPN (see create_client_vpn variable)
      - AWS Direct Connect
      - Transit Gateway with on-prem connectivity
    
    SSM is intended for CLI verification and troubleshooting only.
    ================================================================================
  EOT
}
