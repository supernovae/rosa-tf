#------------------------------------------------------------------------------
# GitOps Layer Resources Module
#
# Consolidates all AWS infrastructure required by GitOps layers into a single
# module. This keeps environment configurations DRY - they just enable
# layers and this module handles the infrastructure.
#
# Architecture:
#   - Terminal: No infrastructure needed (operator only)
#   - OADP: S3 bucket + IAM role for Velero
#   - Virtualization: No infrastructure here - use machine_pools in tfvars
#   - Monitoring: S3 bucket + IAM role for Loki
#   - Cert-Manager: IAM role for Route53 + optional hosted zone
#
# Adding a new layer:
#   1. Add enable_layer_* variable
#   2. Add layer-specific config variables
#   3. Add module call or resources here
#   4. Add outputs
#   See docs/GITOPS-LAYERS-GUIDE.md for complete guide.
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

#------------------------------------------------------------------------------
# OADP Resources (S3 + IAM)
#------------------------------------------------------------------------------

module "oadp" {
  source = "../oadp"
  count  = var.enable_layer_oadp ? 1 : 0

  cluster_name          = var.cluster_name
  oidc_endpoint_url     = var.oidc_endpoint_url
  kms_key_arn           = var.kms_key_arn
  backup_retention_days = var.oadp_backup_retention_days

  tags = var.tags
}

#------------------------------------------------------------------------------
# Virtualization
#
# No AWS infrastructure is created here. Users add bare metal nodes via
# the standard machine_pools variable in their tfvars:
#
#   machine_pools = [
#     {
#       name          = "virt"
#       instance_type = "m6i.metal"
#       replicas      = 2
#       labels        = { "node-role.kubernetes.io/virtualization" = "" }
#       taints        = [{ key = "virtualization", value = "true", schedule_type = "NoSchedule" }]
#     }
#   ]
#
# The operator module installs OpenShift Virtualization operator and
# HyperConverged CR using virt_node_selector and virt_tolerations.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Monitoring Resources (S3 + IAM for Loki)
#------------------------------------------------------------------------------

module "monitoring" {
  source = "../monitoring"
  count  = var.enable_layer_monitoring ? 1 : 0

  cluster_name       = var.cluster_name
  oidc_endpoint_url  = var.oidc_endpoint_url
  aws_region         = var.aws_region
  kms_key_arn        = var.kms_key_arn
  log_retention_days = var.monitoring_retention_days
  is_govcloud        = var.is_govcloud
  openshift_version  = var.openshift_version

  tags = var.tags
}

#------------------------------------------------------------------------------
# Cert-Manager Resources (IAM + optional Route53 Hosted Zone)
#------------------------------------------------------------------------------

module "certmanager" {
  source = "../certmanager"
  count  = var.enable_layer_certmanager ? 1 : 0

  cluster_name         = var.cluster_name
  oidc_endpoint_url    = var.oidc_endpoint_url
  aws_region           = var.aws_region
  hosted_zone_id       = var.certmanager_hosted_zone_id
  hosted_zone_domain   = var.certmanager_hosted_zone_domain
  create_hosted_zone   = var.certmanager_create_hosted_zone
  enable_dnssec        = var.certmanager_enable_dnssec
  enable_query_logging = var.certmanager_enable_query_logging
  kms_key_arn          = var.kms_key_arn
  is_govcloud          = var.is_govcloud

  # Custom ingress configuration
  ingress_enabled            = var.certmanager_ingress_enabled
  ingress_domain             = var.certmanager_ingress_domain
  ingress_visibility         = var.certmanager_ingress_visibility
  ingress_replicas           = var.certmanager_ingress_replicas
  ingress_route_selector     = var.certmanager_ingress_route_selector
  ingress_namespace_selector = var.certmanager_ingress_namespace_selector

  tags = var.tags
}

#------------------------------------------------------------------------------
# NetApp Storage Resources (FSx ONTAP + IAM for Trident)
#------------------------------------------------------------------------------

module "netapp_storage" {
  source = "../netapp-storage"
  count  = var.enable_layer_netapp_storage ? 1 : 0

  cluster_name       = var.cluster_name
  vpc_id             = var.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = var.private_subnet_ids
  oidc_endpoint_url  = var.oidc_endpoint_url
  aws_account_id     = data.aws_caller_identity.current.account_id
  kms_key_arn        = var.kms_key_arn

  # FSx-specific config
  deployment_type          = var.fsx_deployment_type
  storage_capacity_gb      = var.fsx_storage_capacity_gb
  throughput_capacity_mbps = var.fsx_throughput_capacity_mbps
  fsx_admin_password       = var.fsx_admin_password

  # Networking
  create_dedicated_subnets = var.fsx_create_dedicated_subnets
  dedicated_subnet_cidrs   = var.fsx_dedicated_subnet_cidrs
  availability_zones       = var.availability_zones
  private_route_table_ids  = var.private_route_table_ids

  tags = var.tags
}

#------------------------------------------------------------------------------
# OpenShift AI Resources (S3 + IAM for RHOAI)
#------------------------------------------------------------------------------

module "openshift_ai" {
  source = "../openshift-ai"
  count  = var.enable_layer_openshift_ai && var.openshift_ai_create_s3 ? 1 : 0

  cluster_name        = var.cluster_name
  oidc_endpoint_url   = var.oidc_endpoint_url
  aws_region          = var.aws_region
  kms_key_arn         = var.kms_key_arn
  data_retention_days = var.openshift_ai_data_retention_days
  is_govcloud         = var.is_govcloud

  tags = var.tags
}

#------------------------------------------------------------------------------
# Terminal Resources
# (No infrastructure needed - operator deployment only)
#------------------------------------------------------------------------------

# Terminal layer requires no AWS infrastructure.
# The operator module handles installing the Web Terminal operator.
