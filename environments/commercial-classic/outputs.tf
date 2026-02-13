#------------------------------------------------------------------------------
# Cluster Outputs
#------------------------------------------------------------------------------

output "cluster_id" {
  description = "The unique identifier of the ROSA cluster."
  value       = module.rosa_cluster.cluster_id
}

output "cluster_api_url" {
  description = "URL of the OpenShift API server."
  value       = module.rosa_cluster.api_url
}

output "cluster_console_url" {
  description = "URL of the OpenShift web console."
  value       = module.rosa_cluster.console_url
}

output "cluster_domain" {
  description = "DNS domain of the cluster."
  value       = module.rosa_cluster.domain
}

output "cluster_infra_id" {
  description = "Infrastructure ID of the cluster."
  value       = module.rosa_cluster.infra_id
}

output "cluster_state" {
  description = "Current state of the cluster."
  value       = module.rosa_cluster.state
}

output "cluster_version" {
  description = "Current OpenShift version running on the cluster."
  value       = module.rosa_cluster.current_version
}

#------------------------------------------------------------------------------
# Authentication Outputs
#------------------------------------------------------------------------------

output "cluster_admin_username" {
  description = "Username for cluster admin (if created)."
  value       = module.rosa_cluster.admin_username
}

output "cluster_admin_password" {
  description = "Password for cluster admin (if created)."
  value       = module.rosa_cluster.admin_password
  sensitive   = true
}

output "oidc_config_id" {
  description = "ID of the OIDC configuration."
  value       = module.rosa_cluster.oidc_config_id
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL."
  value       = module.rosa_cluster.oidc_endpoint_url
}

#------------------------------------------------------------------------------
# VPC Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC."
  value       = local.effective_vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = local.effective_vpc_cidr
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = local.effective_private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (empty if egress_type != 'nat' or BYO-VPC)."
  value       = local.effective_public_subnet_ids
}

output "availability_zones" {
  description = "Availability zones used by the cluster."
  value       = local.effective_availability_zones
}

output "byo_vpc" {
  description = "Whether the cluster is using an existing (BYO) VPC."
  value       = local.is_byo_vpc
}

output "private_route_table_ids" {
  description = "IDs of the private route tables (empty if BYO-VPC)."
  value       = local.is_byo_vpc ? [] : module.vpc[0].private_route_table_ids
}

output "nat_gateway_ips" {
  description = "Elastic IP addresses of NAT gateways (empty if egress_type != 'nat' or BYO-VPC)."
  value       = local.is_byo_vpc ? [] : module.vpc[0].nat_gateway_ips
}

output "egress_type" {
  description = "The egress type configured for this VPC (nat, tgw, proxy, or byo-vpc)."
  value       = local.is_byo_vpc ? "byo-vpc" : module.vpc[0].egress_type
}

output "vpc_flow_logs_enabled" {
  description = "Whether VPC flow logs are enabled (false if BYO-VPC)."
  value       = local.is_byo_vpc ? false : module.vpc[0].flow_logs_enabled
}

output "vpc_flow_logs_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC flow logs (null if disabled or BYO-VPC)."
  value       = local.is_byo_vpc ? null : module.vpc[0].flow_logs_log_group_arn
}

#------------------------------------------------------------------------------
# IAM Outputs
#------------------------------------------------------------------------------

output "account_role_prefix" {
  description = "Prefix used for account IAM roles."
  value       = module.iam_roles.account_role_prefix
}

output "operator_role_prefix" {
  description = "Prefix used for operator IAM roles."
  value       = module.iam_roles.operator_role_prefix
}

output "account_roles_arn" {
  description = "ARNs of the account IAM roles (created by Terraform)."
  value       = module.iam_roles.account_roles_arn
}

output "operator_roles_arn" {
  description = "ARNs of the operator IAM roles (created by Terraform)."
  value       = module.iam_roles.operator_roles
}

output "operator_role_names" {
  description = "Names of the operator IAM roles."
  value       = module.iam_roles.operator_role_names
}

#------------------------------------------------------------------------------
# KMS Outputs (Separate keys for blast radius containment)
#------------------------------------------------------------------------------

output "cluster_kms_mode" {
  description = "Cluster KMS mode: provider_managed, create, or existing."
  value       = var.cluster_kms_mode
}

output "cluster_kms_key_arn" {
  description = "Cluster KMS key ARN for ROSA workers/etcd (null if provider_managed)."
  value       = local.cluster_kms_key_arn
}

output "infra_kms_mode" {
  description = "Infrastructure KMS mode: provider_managed, create, or existing."
  value       = var.infra_kms_mode
}

output "infra_kms_key_arn" {
  description = "Infrastructure KMS key ARN for jump host/CloudWatch/S3/VPN (null if provider_managed)."
  value       = local.infra_kms_key_arn
}

#------------------------------------------------------------------------------
# ECR Information (Optional)
#------------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "ECR repository URL for docker push/pull (empty if create_ecr = false)."
  value       = var.create_ecr ? module.ecr[0].repository_url : ""
}

output "ecr_registry_url" {
  description = "ECR registry URL for docker login (empty if create_ecr = false)."
  value       = var.create_ecr ? module.ecr[0].registry_url : ""
}

#------------------------------------------------------------------------------
# Jump Host Outputs
#------------------------------------------------------------------------------

output "jumphost_instance_id" {
  description = "Instance ID of the SSM jump host (use for SSM sessions)."
  value       = var.create_jumphost ? module.jumphost[0].instance_id : null
}

output "jumphost_private_ip" {
  description = "Private IP address of the jump host."
  value       = var.create_jumphost ? module.jumphost[0].private_ip : null
}

output "ssm_session_command" {
  description = "AWS CLI command to start an SSM session to the jump host."
  value       = var.create_jumphost ? module.jumphost[0].ssm_session_command : null
}

output "ssm_access_instructions" {
  description = "Complete instructions for accessing cluster via SSM."
  value       = var.create_jumphost ? module.jumphost[0].ssm_access_instructions : null
}

#------------------------------------------------------------------------------
# Cluster Authentication Outputs
#------------------------------------------------------------------------------

output "cluster_auth_summary" {
  description = <<-EOT
    Cluster authentication status for GitOps installation.
    If authenticated=false, GitOps was skipped. Check 'error' field for details.
    For private clusters, ensure network connectivity to cluster VPC before re-running.
    See: modules/gitops-layers/operator/README.md
  EOT
  value = var.install_gitops && length(module.cluster_auth) > 0 ? module.cluster_auth[0].auth_summary : {
    enabled       = false
    authenticated = false
    host          = ""
    username      = ""
    error         = "install_gitops is false"
  }
}

#------------------------------------------------------------------------------
# GitOps Outputs
#------------------------------------------------------------------------------

output "gitops_installed" {
  description = "Whether GitOps was successfully installed."
  value       = var.install_gitops && length(module.gitops) > 0
}

output "gitops_namespace" {
  description = "Namespace where GitOps operator is installed."
  value       = var.install_gitops && length(module.gitops) > 0 ? module.gitops[0].namespace : null
}

output "gitops_argocd_url" {
  description = "URL of the ArgoCD console (if installed)."
  value       = var.install_gitops && length(module.gitops) > 0 ? module.gitops[0].argocd_url : null
}

output "gitops_status" {
  description = "GitOps installation status and next steps if not installed."
  value = var.install_gitops ? (
    length(module.gitops) > 0 ? {
      status  = "installed"
      message = "GitOps operator installed successfully"
      } : {
      status  = "skipped"
      message = <<-EOT
        GitOps installation was SKIPPED due to connectivity or authentication issues.
        
        Check cluster_auth_summary output for details.
        
        For private clusters:
        1. Establish network connectivity to cluster VPC
           - Connect via Client VPN (see vpn_endpoint_id output)
           - Or use jump host / bastion
           - Or configure Transit Gateway / Direct Connect
        2. Re-run: terraform apply -var-file=<your>.tfvars
        
        For public clusters:
        - Verify cluster API is accessible from this machine
        - Check htpasswd IDP is configured on cluster
        
        Documentation: modules/gitops-layers/operator/README.md
      EOT
    }
    ) : {
    status  = "disabled"
    message = "Set install_gitops=true to enable"
  }
}

#------------------------------------------------------------------------------
# Machine Pools Outputs
#------------------------------------------------------------------------------

output "machine_pools_summary" {
  description = "Summary of machine pools (null if none created)."
  value       = length(var.machine_pools) > 0 ? module.machine_pools[0].machine_pools : null
}

output "machine_pool_names" {
  description = "List of created machine pool names."
  value       = length(var.machine_pools) > 0 ? module.machine_pools[0].pool_names : []
}

#------------------------------------------------------------------------------
# Client VPN Outputs
#------------------------------------------------------------------------------

output "vpn_endpoint_id" {
  description = "ID of the Client VPN endpoint (null if not created)."
  value       = var.create_client_vpn ? module.client_vpn[0].vpn_endpoint_id : null
}

output "vpn_endpoint_dns" {
  description = "DNS name of the Client VPN endpoint (null if not created)."
  value       = var.create_client_vpn ? module.client_vpn[0].vpn_endpoint_dns : null
}

output "vpn_client_config_path" {
  description = "Path to the OpenVPN client configuration file (null if not created)."
  value       = var.create_client_vpn ? module.client_vpn[0].client_config_path : null
}

output "vpn_connection_instructions" {
  description = "Instructions for connecting via VPN (null if not created)."
  value       = var.create_client_vpn ? module.client_vpn[0].connection_instructions : null
}

#------------------------------------------------------------------------------
# Connection Information
#------------------------------------------------------------------------------

output "connection_info" {
  description = "Instructions for connecting to the cluster."
  value = <<-EOT
    
    ================================================================================
    ROSA Classic Cluster: ${var.cluster_name}
    ================================================================================
    
    Cluster API:     ${module.rosa_cluster.api_url}
    Console URL:     ${module.rosa_cluster.console_url}
    Cluster Domain:  ${module.rosa_cluster.domain}
    
    ${var.create_jumphost ? "Jump Host ID:    ${module.jumphost[0].instance_id}" : "Jump Host:       Not created"}
    
    --------------------------------------------------------------------------------
    SSM PREREQUISITES
    --------------------------------------------------------------------------------
    
    Install AWS Session Manager Plugin (required for SSM port forwarding):
    - macOS:   brew install --cask session-manager-plugin
    - Linux:   https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
    - Windows: Download MSI from AWS docs above
    
    ${var.create_jumphost ? <<-JUMP
    --------------------------------------------------------------------------------
    CLI ACCESS VIA SSM JUMPHOST
    --------------------------------------------------------------------------------
    
    1. Connect to the jumphost (inside VPC, can access all cluster endpoints):
    
       aws ssm start-session --target ${module.jumphost[0].instance_id} --region ${var.aws_region}
    
    2. Once connected, login to OpenShift:
    
       oc login https://api.${module.rosa_cluster.domain}:6443 -u ${module.rosa_cluster.admin_username}
       # Password: terraform output -raw cluster_admin_password
    
    3. Use oc/kubectl commands directly from the jumphost.
    
    --------------------------------------------------------------------------------
    WEB CONSOLE & WORKSTATION ACCESS
    --------------------------------------------------------------------------------
    
    For web console or local workstation API access, configure:
      - AWS Client VPN (create_client_vpn = true)
      - AWS Direct Connect
      - Transit Gateway with on-prem connectivity
    JUMP
: "No jump host created. Configure VPN or Direct Connect for cluster access."}
    
    ================================================================================
  EOT
}

#------------------------------------------------------------------------------
# Deployment Timing (when enable_timing = true)
#------------------------------------------------------------------------------

output "deployment_timing" {
  description = "Deployment timing summary (only populated when enable_timing = true)."
  value       = var.enable_timing ? module.timing.timing_summary : null
}

#------------------------------------------------------------------------------
# Cert-Manager Ingress Outputs
#------------------------------------------------------------------------------

output "certmanager_ingress_enabled" {
  description = "Whether a custom IngressController was created for the cert-manager domain."
  value       = var.install_gitops && length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_ingress_enabled : false
}

output "certmanager_ingress_domain" {
  description = <<-EOT
    Domain served by the custom IngressController.
    
    After apply, verify the custom ingress is working:
      oc get ingresscontroller custom-apps -n openshift-ingress-operator
      oc get svc router-custom-apps -n openshift-ingress
    
    The Route53 CNAME record *.domain -> NLB is created automatically.
  EOT
  value       = var.install_gitops && length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_ingress_domain : ""
}

output "certmanager_ingress_visibility" {
  description = "Visibility of the custom IngressController NLB (private or public)."
  value       = var.install_gitops && length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_ingress_visibility : ""
}

#------------------------------------------------------------------------------
# S3 Bucket Cleanup Notice
#------------------------------------------------------------------------------

output "s3_buckets_requiring_manual_cleanup" {
  description = <<-EOT
    S3 buckets that require manual cleanup after terraform destroy.
    
    IMPORTANT: These buckets are NOT automatically deleted to prevent
    accidental data loss. After destroying the cluster, manually delete
    if you no longer need the data:
    
      aws s3 rb s3://BUCKET_NAME --force
  EOT
  value       = var.install_gitops && length(module.gitops_resources) > 0 ? module.gitops_resources[0].s3_buckets_requiring_manual_cleanup : []
}
