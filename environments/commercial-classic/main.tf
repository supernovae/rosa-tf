#------------------------------------------------------------------------------
# Provider Configuration
#------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "rosa-classic"
      ManagedBy   = "terraform"
      ClusterName = var.cluster_name
    }
  }

  # ROSA installer manages kubernetes.io/cluster/* tags on subnets and
  # security groups. Ignore them so Phase 2 (and subsequent) applies
  # don't produce unnecessary modifications.
  ignore_tags {
    key_prefixes = ["kubernetes.io/cluster/"]
  }
}

# RHCS Provider for Commercial AWS
#
# Uses service account authentication (client_id + client_secret).
# The offline OCM token is deprecated for commercial cloud.
#
# Create a service account at:
#   https://console.redhat.com/iam/service-accounts
#
# Set credentials via environment variables:
#   export TF_VAR_rhcs_client_id="your-client-id"
#   export TF_VAR_rhcs_client_secret="your-client-secret"
#
provider "rhcs" {
  url           = "https://api.openshift.com"
  client_id     = var.rhcs_client_id
  client_secret = var.rhcs_client_secret
}

# Kubernetes provider for native resource management (GitOps layers).
#
# Authentication priority:
#   1. gitops_cluster_token (SA token from previous bootstrap) -- no OAuth needed
#   2. cluster_auth module (OAuth bootstrap) -- first run only
provider "kubernetes" {
  host     = local.effective_k8s_host
  token    = local.effective_k8s_token
  insecure = true
}

provider "kubectl" {
  host             = local.effective_k8s_host
  token            = local.effective_k8s_token
  load_config_file = false
  insecure         = true
}

#------------------------------------------------------------------------------
# Validation Checks
#------------------------------------------------------------------------------

# Validate GitOps configuration before any resources are created/destroyed
# This uses a null_resource with precondition to FAIL (not warn) if config is invalid
# Layers depend on the GitOps operator (ArgoCD) which is installed by install_gitops
resource "null_resource" "validate_gitops_config" {
  lifecycle {
    precondition {
      condition = var.install_gitops || !(
        var.enable_layer_terminal ||
        var.enable_layer_oadp ||
        var.enable_layer_virtualization ||
        var.enable_layer_monitoring
      )
      error_message = <<-EOT
        GitOps layers require install_gitops = true.

        You have enabled one or more GitOps layers:
          - enable_layer_terminal:       ${var.enable_layer_terminal}
          - enable_layer_oadp:           ${var.enable_layer_oadp}
          - enable_layer_virtualization: ${var.enable_layer_virtualization}
          - enable_layer_monitoring:     ${var.enable_layer_monitoring}

        But install_gitops is set to: ${var.install_gitops}

        To fix, either:
          1. Set install_gitops = true to enable GitOps and layers
          2. Set all enable_layer_* variables to false

        NOTE: S3 buckets (Loki logs, OADP backups) are created via CloudFormation
        with DeletionPolicy: Retain and will NOT be deleted on destroy. You are
        responsible for manually cleaning up retained buckets when no longer needed.
      EOT
    }
  }
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"

  # Filter to only AZs that are fully opted-in (excludes Local Zones, Wavelength, etc.)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Filter AZs that support the instance types we need (proxy for NAT Gateway support)
# AZs like us-east-1e don't support NAT Gateway or many instance types
data "aws_ec2_instance_type_offerings" "available" {
  filter {
    name   = "instance-type"
    values = ["m6i.xlarge"] # Standard ROSA worker type
  }

  filter {
    name   = "location"
    values = data.aws_availability_zones.available.names
  }

  location_type = "availability-zone"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

#------------------------------------------------------------------------------
# BYO-VPC Data Sources
#------------------------------------------------------------------------------

data "aws_vpc" "existing" {
  count = var.existing_vpc_id != null ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_subnet" "existing_private" {
  count = var.existing_vpc_id != null ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]
}

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------

locals {
  # Cluster type - single source of truth for all modules
  # Classic clusters have SRE-managed openshift-monitoring namespace
  cluster_type = "classic"

  # Derive API/console URLs from the cluster domain (always populated).
  # The RHCS classic provider may leave api_url/console_url empty even when
  # the cluster is ready. Deriving from domain is deterministic and reliable.
  # ROSA API URLs follow the pattern: https://api.<domain>:6443
  effective_api_url     = "https://api.${module.rosa_cluster.domain}:6443"
  effective_console_url = "https://console-openshift-console.apps.${module.rosa_cluster.domain}"

  # Kubernetes provider host: cluster API when gitops enabled, dummy otherwise.
  # With two-phase deployment, Phase 1 always has install_gitops=false (localhost)
  # and Phase 2 always has the cluster in state (domain is known).
  effective_k8s_host = var.install_gitops ? local.effective_api_url : "https://localhost"

  # Kubernetes provider token: SA token (steady state) or OAuth token (bootstrap)
  # Priority: gitops_cluster_token (from previous run) > cluster_auth OAuth > empty
  effective_k8s_token = (
    var.gitops_cluster_token != null
    ? var.gitops_cluster_token
    : try(module.cluster_auth[0].token, "")
  )

  # Partition detection - derived from AWS provider, not hardcoded
  partition   = data.aws_partition.current.partition
  is_govcloud = local.partition == "aws-us-gov"

  # AZs that support both general availability AND required instance types
  # This filters out AZs like us-east-1e that don't support NAT Gateway
  supported_azs = sort(distinct(data.aws_ec2_instance_type_offerings.available.locations))

  # Determine AZ count based on deployment mode
  az_count = var.multi_az ? 3 : 1

  # Use provided AZs or auto-select from supported AZs
  availability_zones = var.availability_zones != null ? var.availability_zones : slice(
    local.supported_azs,
    0,
    min(local.az_count, length(local.supported_azs))
  )

  # Account and operator role prefixes (cluster-scoped)
  # ROSA Classic uses cluster-scoped roles - each cluster has its own roles
  # This ensures clean teardown without affecting other clusters
  account_role_prefix  = coalesce(var.account_role_prefix, var.cluster_name)
  operator_role_prefix = coalesce(var.operator_role_prefix, var.cluster_name)

  # OpenShift version
  openshift_version = var.openshift_version

  # Calculate subnet CIDRs based on AZ count
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i)
  ]

  # Public subnets for NAT gateways and optionally for public clusters
  public_subnet_cidrs = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 3)
  ]

  # NAT gateway count follows AZ count: single-AZ = single NAT, multi-AZ = NAT per AZ
  use_single_nat = !var.multi_az

  # BYO-VPC: indirection layer for all network references
  # When existing_vpc_id is set, use provided values instead of module.vpc outputs
  is_byo_vpc                   = var.existing_vpc_id != null
  effective_vpc_id             = local.is_byo_vpc ? var.existing_vpc_id : module.vpc[0].vpc_id
  effective_vpc_cidr           = local.is_byo_vpc ? data.aws_vpc.existing[0].cidr_block : module.vpc[0].vpc_cidr
  effective_private_subnet_ids = local.is_byo_vpc ? var.existing_private_subnet_ids : module.vpc[0].private_subnet_ids
  effective_public_subnet_ids  = local.is_byo_vpc ? coalesce(var.existing_public_subnet_ids, []) : module.vpc[0].public_subnet_ids
  effective_availability_zones = local.is_byo_vpc ? data.aws_subnet.existing_private[*].availability_zone : local.availability_zones
  effective_az_count           = local.is_byo_vpc ? length(var.existing_private_subnet_ids) : local.az_count
  effective_multi_az           = local.effective_az_count >= 3

  # Common tags
  common_tags = {
    for k, v in merge(
      {
        "rosa_cluster"     = var.cluster_name
        "rosa_environment" = "commercial"
        "rosa_topology"    = var.multi_az ? "multi-az" : "single-az"
        "rosa_access"      = var.private_cluster ? "private" : "public"
      },
      var.tags
    ) : k => v if v != null && v != ""
  }
}

#------------------------------------------------------------------------------
# Regional Availability Zone Validation
#
# Some regions have limited AZs (e.g., us-west-1 has only 2 AZs).
# ROSA multi-AZ requires 3 AZs. This check prevents deployment failures.
#------------------------------------------------------------------------------

check "multi_az_region_support" {
  assert {
    condition     = !var.multi_az || length(local.supported_azs) >= 3
    error_message = <<-EOT
      Multi-AZ deployment requires at least 3 availability zones.
      
      Region ${var.aws_region} has only ${length(local.supported_azs)} supported AZ(s): ${join(", ", local.supported_azs)}
      
      Options:
      1. Set multi_az = false for single-AZ deployment
      2. Use a region with 3+ AZs (e.g., us-east-1, us-west-2, eu-west-1)
      
      Regions with limited AZs include:
      - us-west-1 (2 AZs) - Single-AZ Classic only
    EOT
  }
}

#------------------------------------------------------------------------------
# KMS Configuration
#
# Two separate keys with STRICT SEPARATION for blast radius containment:
# - Cluster KMS: ROSA workers and etcd ONLY (Red Hat expected policy)
# - Infrastructure KMS: Jump host, CloudWatch, S3/OADP, VPN ONLY
#
# Three modes for each key:
# - provider_managed (DEFAULT): Uses AWS managed aws/ebs key - no KMS costs
# - create: Terraform creates customer-managed key
# - existing: Use customer-provided KMS key ARN
#------------------------------------------------------------------------------

module "kms" {
  source = "../../modules/security/kms"

  # Only instantiate when at least one key needs custom management
  count = (var.cluster_kms_mode != "provider_managed" || var.infra_kms_mode != "provider_managed") ? 1 : 0

  cluster_name         = var.cluster_name
  account_role_prefix  = local.account_role_prefix
  operator_role_prefix = local.operator_role_prefix

  # Cluster KMS configuration (for ROSA workers, etcd)
  cluster_kms_mode    = var.cluster_kms_mode
  cluster_kms_key_arn = var.cluster_kms_key_arn

  # Infrastructure KMS configuration (for jump host, CloudWatch, S3, VPN)
  infra_kms_mode    = var.infra_kms_mode
  infra_kms_key_arn = var.infra_kms_key_arn

  # Classic clusters don't need HCP-specific permissions
  is_hcp_cluster             = false
  enable_hcp_etcd_encryption = false

  # Common settings
  kms_key_deletion_window = var.kms_key_deletion_window
  tags                    = local.common_tags
}

# Locals to simplify KMS key ARN references with strict separation
locals {
  # Cluster KMS: for ROSA workers and etcd ONLY
  cluster_kms_key_arn = var.cluster_kms_mode == "provider_managed" ? null : module.kms[0].cluster_kms_key_arn

  # Infrastructure KMS: for jump host, CloudWatch, S3, VPN ONLY
  # IMPORTANT: Do NOT use this for ROSA workers (strict separation)
  infra_kms_key_arn = var.infra_kms_mode == "provider_managed" ? null : module.kms[0].infra_kms_key_arn
}

#------------------------------------------------------------------------------
# Module: VPC
# Creates VPC with subnets for public or private cluster deployment
#------------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/networking/vpc"
  count  = var.existing_vpc_id == null ? 1 : 0

  depends_on = [module.kms]

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  private_subnet_cidrs = local.private_subnet_cidrs
  public_subnet_cidrs  = local.public_subnet_cidrs

  # Egress configuration
  egress_type        = var.egress_type
  single_nat_gateway = local.use_single_nat

  transit_gateway_id         = var.transit_gateway_id
  transit_gateway_route_cidr = var.transit_gateway_route_cidr

  # VPC Flow Logs (optional) - uses infrastructure KMS (NOT cluster KMS)
  enable_flow_logs           = var.enable_vpc_flow_logs
  flow_logs_retention_days   = var.flow_logs_retention_days
  infrastructure_kms_key_arn = local.infra_kms_key_arn

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Module: IAM Roles
# Creates OIDC config/provider and operator roles
#------------------------------------------------------------------------------

module "iam_roles" {
  source = "../../modules/security/iam/rosa-classic"

  cluster_name         = var.cluster_name
  account_role_prefix  = local.account_role_prefix
  operator_role_prefix = local.operator_role_prefix
  openshift_version    = var.openshift_version

  # ECR policy for container image pulls
  attach_ecr_policy = var.create_ecr

  # OIDC configuration
  # Defaults to creating new managed OIDC per-cluster
  create_oidc_config          = var.create_oidc_config
  managed_oidc                = var.managed_oidc
  oidc_config_id              = var.oidc_config_id
  oidc_endpoint_url           = var.oidc_endpoint_url
  oidc_private_key_secret_arn = var.oidc_private_key_secret_arn
  installer_role_arn_for_oidc = var.installer_role_arn_for_oidc

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# ECR Repository (Optional)
# Private container registry for custom images
#------------------------------------------------------------------------------

module "ecr" {
  source = "../../modules/registry/ecr"
  count  = var.create_ecr ? 1 : 0

  cluster_name    = var.cluster_name
  repository_name = var.ecr_repository_name
  kms_key_arn     = local.infra_kms_key_arn

  # Lifecycle management - when true, ECR survives cluster destroy
  prevent_destroy = var.ecr_prevent_destroy

  # VPC endpoints for private ECR access (default: enabled)
  # Avoids NAT egress costs and required for zero-egress clusters
  create_vpc_endpoints = var.ecr_create_vpc_endpoints
  vpc_id               = local.effective_vpc_id
  private_subnet_ids   = local.effective_private_subnet_ids
  vpc_cidr             = local.effective_vpc_cidr

  tags = local.common_tags

  depends_on = [module.vpc]
}

#------------------------------------------------------------------------------
# Pre-cluster Infrastructure Check
#------------------------------------------------------------------------------

resource "null_resource" "infrastructure_ready" {
  depends_on = [
    module.vpc,
    module.iam_roles,
    module.kms
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Pre-cluster infrastructure check ==="
      echo "Verifying AWS credentials..."
      aws sts get-caller-identity --region ${var.aws_region}
      echo ""
      echo "Infrastructure ready. Starting cluster creation..."
      echo "Note: Cluster creation takes 45-60 minutes."
    EOT
  }
}

#------------------------------------------------------------------------------
# Destroy Ordering: Wait for AWS to settle after cluster deletion
#
# After ROSA cluster is deleted, AWS resources (ENIs, security groups, load
# balancers) need time to be cleaned up. This wait ensures AWS has reconciled
# before Terraform attempts to delete the VPC.
#
# Dependency chain on destroy:
# 1. Resources using cluster (jumphost, VPN, gitops) destroyed first
# 2. ROSA cluster destroyed
# 3. This wait runs (2 minutes for AWS to settle)
# 4. VPC, KMS, IAM destroyed last
#------------------------------------------------------------------------------

resource "null_resource" "wait_for_cluster_destroy" {
  triggers = {
    cluster_name = var.cluster_name
    vpc_id       = local.effective_vpc_id
    script_path  = "${path.module}/../../scripts/vpc-cleanup.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash \"${self.triggers.script_path}\" \"${self.triggers.vpc_id}\" \"${self.triggers.cluster_name}\""
  }

  depends_on = [module.vpc]
}

#------------------------------------------------------------------------------
# Additional Security Groups (Optional)
#
# Creates or aggregates additional security groups for the cluster.
# IMPORTANT: Security groups can only be attached at cluster CREATION time.
#
# See docs/SECURITY-GROUPS.md for detailed documentation.
#------------------------------------------------------------------------------

module "additional_security_groups" {
  source = "../../modules/networking/security-groups"

  enabled      = var.additional_security_groups_enabled
  cluster_name = var.cluster_name
  cluster_type = local.cluster_type
  vpc_id       = local.effective_vpc_id
  vpc_cidr     = local.effective_vpc_cidr

  # Intra-VPC template (WARNING: permissive rules for development)
  use_intra_vpc_template = var.use_intra_vpc_security_group_template

  # Existing security groups
  existing_compute_security_group_ids       = var.existing_compute_security_group_ids
  existing_control_plane_security_group_ids = var.existing_control_plane_security_group_ids
  existing_infra_security_group_ids         = var.existing_infra_security_group_ids

  # Custom rules
  compute_ingress_rules       = var.compute_security_group_rules.ingress
  compute_egress_rules        = var.compute_security_group_rules.egress
  control_plane_ingress_rules = var.control_plane_security_group_rules.ingress
  control_plane_egress_rules  = var.control_plane_security_group_rules.egress
  infra_ingress_rules         = var.infra_security_group_rules.ingress
  infra_egress_rules          = var.infra_security_group_rules.egress

  tags = local.common_tags

  depends_on = [module.vpc]
}

#------------------------------------------------------------------------------
# Module: ROSA Classic Cluster
# Deploys the ROSA Classic cluster - public or private, with configurable security
#------------------------------------------------------------------------------

module "rosa_cluster" {
  source = "../../modules/cluster/rosa-classic"

  depends_on = [
    null_resource.infrastructure_ready,
    null_resource.wait_for_cluster_destroy,
    module.additional_security_groups,
  ]

  cluster_name                 = var.cluster_name
  openshift_version            = local.openshift_version
  channel_group                = var.channel_group
  upgrade_acknowledgements_for = var.upgrade_acknowledgements_for
  aws_region                   = var.aws_region
  availability_zones           = local.effective_availability_zones

  # VPC Configuration
  # Private cluster: only private subnets (NAT egress handled by VPC routing)
  # Public cluster: both private and public subnets (for public ingress LBs)
  private_subnet_ids = local.effective_private_subnet_ids
  public_subnet_ids  = var.private_cluster ? [] : local.effective_public_subnet_ids
  machine_cidr       = local.effective_vpc_cidr
  pod_cidr           = var.pod_cidr
  service_cidr       = var.service_cidr
  host_prefix        = var.host_prefix

  # Commercial: Configurable cluster access and security
  # Public: API/ingress accessible from internet
  # Private: API/ingress only accessible from within VPC
  private_cluster = var.private_cluster
  fips            = var.fips
  multi_az        = var.multi_az

  # Worker Configuration
  compute_machine_type = var.compute_machine_type
  worker_node_count    = var.worker_node_count
  worker_disk_size     = var.worker_disk_size

  # IAM Configuration
  account_role_prefix  = local.account_role_prefix
  operator_role_prefix = local.operator_role_prefix
  oidc_config_id       = module.iam_roles.oidc_config_id

  # Additional security groups (can only be set at cluster creation time)
  aws_additional_compute_security_group_ids       = module.additional_security_groups.compute_security_group_ids
  aws_additional_control_plane_security_group_ids = module.additional_security_groups.control_plane_security_group_ids
  aws_additional_infra_security_group_ids         = module.additional_security_groups.infra_security_group_ids

  # Cluster KMS encryption (uses cluster_kms_key_arn ONLY - strict separation)
  # provider_managed mode: null (uses AWS managed aws/ebs key)
  # create/existing mode: customer-managed KMS key
  etcd_encryption = var.etcd_encryption && local.cluster_kms_key_arn != null
  kms_key_arn     = local.cluster_kms_key_arn

  # Admin User
  create_admin_user = var.create_admin_user
  admin_username    = var.admin_username

  # Cluster Autoscaler
  cluster_autoscaler_enabled                  = var.cluster_autoscaler_enabled
  autoscaler_max_nodes_total                  = var.autoscaler_max_nodes_total
  autoscaler_scale_down_enabled               = var.autoscaler_scale_down_enabled
  autoscaler_scale_down_utilization_threshold = var.autoscaler_scale_down_utilization_threshold
  autoscaler_scale_down_delay_after_add       = var.autoscaler_scale_down_delay_after_add
  autoscaler_scale_down_unneeded_time         = var.autoscaler_scale_down_unneeded_time

  # Workload Monitoring
  disable_workload_monitoring = var.disable_workload_monitoring

  # Proxy Configuration
  http_proxy              = var.http_proxy
  https_proxy             = var.https_proxy
  no_proxy                = var.no_proxy
  additional_trust_bundle = var.additional_trust_bundle

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Module: Jump Host (Optional)
# Creates an SSM-enabled EC2 instance for cluster access
#------------------------------------------------------------------------------

module "jumphost" {
  source = "../../modules/networking/jumphost"
  count  = var.create_jumphost ? 1 : 0

  depends_on = [module.vpc, module.kms, module.rosa_cluster]

  cluster_name        = var.cluster_name
  vpc_id              = local.effective_vpc_id
  subnet_id           = local.effective_private_subnet_ids[0]
  instance_type       = var.jumphost_instance_type
  ami_id              = var.jumphost_ami_id
  cluster_api_url     = local.effective_api_url
  cluster_console_url = local.effective_console_url
  cluster_domain      = module.rosa_cluster.domain

  # Infrastructure KMS key for jump host encryption (null = use AWS default)
  # Uses infra_kms_key_arn - NOT cluster KMS (strict separation)
  kms_key_arn = local.infra_kms_key_arn

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Module: Client VPN (Optional)
#------------------------------------------------------------------------------

module "client_vpn" {
  source = "../../modules/networking/client-vpn"
  count  = var.create_client_vpn ? 1 : 0

  depends_on = [module.vpc, module.kms, module.rosa_cluster]

  cluster_name   = var.cluster_name
  cluster_domain = module.rosa_cluster.domain
  vpc_id         = local.effective_vpc_id
  vpc_cidr       = local.effective_vpc_cidr

  subnet_ids = [local.effective_private_subnet_ids[0]]

  client_cidr_block     = var.vpn_client_cidr_block
  split_tunnel          = var.vpn_split_tunnel
  session_timeout_hours = var.vpn_session_timeout_hours

  service_cidr = var.service_cidr

  # Infrastructure KMS for VPN encryption (null = use AWS default)
  # Uses infra_kms_key_arn - NOT cluster KMS (strict separation)
  kms_key_arn = local.infra_kms_key_arn

  tags = local.common_tags
}

# Validate: BYO-VPC requires private subnet IDs and consistent public subnet count
resource "terraform_data" "validate_byo_vpc" {
  count = var.existing_vpc_id != null ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.existing_private_subnet_ids != null && length(var.existing_private_subnet_ids) > 0
      error_message = "existing_private_subnet_ids is required when existing_vpc_id is set."
    }
    precondition {
      condition     = var.existing_public_subnet_ids == null ? true : length(var.existing_public_subnet_ids) == length(var.existing_private_subnet_ids)
      error_message = "existing_public_subnet_ids must have the same count as existing_private_subnet_ids (same AZ topology)."
    }
    precondition {
      condition     = var.private_cluster || (var.existing_public_subnet_ids != null ? length(var.existing_public_subnet_ids) > 0 : false)
      error_message = "Public clusters require existing_public_subnet_ids when using BYO-VPC."
    }
  }
}

#------------------------------------------------------------------------------
# Module: GitOps Layer Resources (Optional)
#
# Consolidated module for all GitOps layer infrastructure (S3, IAM, pools).
# See docs/GITOPS-LAYERS-GUIDE.md for adding new layers.
#
# GITOPS-VAR-CHAIN: When adding a new GitOps variable, update ALL of these files:
#   1. modules/gitops-layers/operator/variables.tf   (or resources/variables.tf)
#   2. modules/gitops-layers/shared/layer-variables.tf (if shared across layers)
#   3. environments/*/variables.tf                    (all 4 environments)
#   4. environments/*/main.tf                         (passthrough in module blocks below)
#   5. gitops-layers/layers/*/*.yaml.tftpl            (if used in YAML templates)
#------------------------------------------------------------------------------

module "gitops_resources" {
  source = "../../modules/gitops-layers/resources"
  count  = var.install_gitops ? 1 : 0

  depends_on = [module.iam_roles, module.rosa_cluster]

  cluster_name      = var.cluster_name
  cluster_type      = local.cluster_type
  oidc_endpoint_url = module.iam_roles.oidc_endpoint_url
  aws_region        = var.aws_region
  kms_key_arn       = local.infra_kms_key_arn

  # Layer enable flags
  enable_layer_terminal       = var.enable_layer_terminal
  enable_layer_oadp           = var.enable_layer_oadp
  enable_layer_virtualization = var.enable_layer_virtualization
  enable_layer_monitoring     = var.enable_layer_monitoring
  enable_layer_certmanager    = var.enable_layer_certmanager

  # Layer-specific config
  oadp_backup_retention_days = var.oadp_backup_retention_days

  # Monitoring config
  monitoring_retention_days          = var.monitoring_retention_days
  monitoring_prometheus_storage_size = var.monitoring_prometheus_storage_size
  monitoring_storage_class           = var.monitoring_storage_class
  is_govcloud                        = local.is_govcloud
  openshift_version                  = var.openshift_version

  # Cert-Manager config (for AWS resource creation)
  certmanager_hosted_zone_id             = var.certmanager_hosted_zone_id
  certmanager_hosted_zone_domain         = var.certmanager_hosted_zone_domain
  certmanager_create_hosted_zone         = var.certmanager_create_hosted_zone
  certmanager_enable_dnssec              = var.certmanager_enable_dnssec
  certmanager_enable_query_logging       = var.certmanager_enable_query_logging
  certmanager_ingress_enabled            = var.certmanager_ingress_enabled
  certmanager_ingress_domain             = var.certmanager_ingress_domain
  certmanager_ingress_visibility         = var.certmanager_ingress_visibility
  certmanager_ingress_replicas           = var.certmanager_ingress_replicas
  certmanager_ingress_route_selector     = var.certmanager_ingress_route_selector
  certmanager_ingress_namespace_selector = var.certmanager_ingress_namespace_selector

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Module: Cluster Authentication (for GitOps)
#
# Obtains an OAuth token for the kubernetes provider using the htpasswd
# identity provider credentials created with the cluster.
#
# IMPORTANT: This requires the htpasswd IDP to be present on the cluster.
# See modules/gitops-layers/operator/README.md for Day 0 vs Day 2 guidance.
#------------------------------------------------------------------------------

module "cluster_auth" {
  source = "../../modules/utility/cluster-auth"
  count  = var.install_gitops ? 1 : 0

  depends_on = [module.rosa_cluster]

  enabled       = var.install_gitops
  api_url       = local.effective_api_url
  oauth_url     = var.gitops_oauth_url != null ? var.gitops_oauth_url : ""
  cluster_token = var.gitops_cluster_token != null ? var.gitops_cluster_token : ""
  username      = module.rosa_cluster.admin_username
  password      = module.rosa_cluster.admin_password
}

#------------------------------------------------------------------------------
# Module: GitOps (Optional)
#
# Installs OpenShift GitOps (ArgoCD) and configures the GitOps Layers framework.
# Uses native kubernetes/kubectl providers for cluster resource management.
#
# NOTE: GitOps will only succeed if:
# 1. Cluster is reachable from Terraform runner
# 2. cluster_auth module obtained a valid token
# For private clusters, establish VPC connectivity first.
#------------------------------------------------------------------------------

module "gitops" {
  source = "../../modules/gitops-layers/operator"
  count  = var.install_gitops ? 1 : 0

  depends_on = [
    module.rosa_cluster,
    module.cluster_auth,
    module.gitops_resources
  ]

  cluster_name           = var.cluster_name
  cluster_api_url        = local.effective_api_url
  cluster_token          = length(module.cluster_auth) > 0 ? module.cluster_auth[0].token : ""
  terraform_sa_name      = var.terraform_sa_name
  terraform_sa_namespace = var.terraform_sa_namespace
  skip_k8s_destroy       = var.skip_k8s_destroy
  cluster_type           = local.cluster_type
  aws_region             = var.aws_region
  aws_account_id         = data.aws_caller_identity.current.account_id

  gitops_repo_url      = coalesce(var.gitops_repo_url, "https://github.com/supernovae/rosa-tf.git")
  gitops_repo_path     = coalesce(var.gitops_repo_path, "gitops-layers/layers")
  gitops_repo_revision = coalesce(var.gitops_repo_revision, "main")

  enable_layer_terminal       = var.enable_layer_terminal
  enable_layer_oadp           = var.enable_layer_oadp
  enable_layer_virtualization = var.enable_layer_virtualization
  enable_layer_monitoring     = var.enable_layer_monitoring
  enable_layer_certmanager    = var.enable_layer_certmanager

  # Layer resources from consolidated module
  oadp_bucket_name           = length(module.gitops_resources) > 0 ? module.gitops_resources[0].oadp_bucket_name : ""
  oadp_role_arn              = length(module.gitops_resources) > 0 ? module.gitops_resources[0].oadp_role_arn : ""
  oadp_backup_retention_days = var.oadp_backup_retention_days

  virt_node_selector = var.virt_node_selector
  virt_tolerations   = var.virt_tolerations

  # Monitoring resources from consolidated module
  monitoring_bucket_name             = length(module.gitops_resources) > 0 ? module.gitops_resources[0].monitoring_bucket_name : ""
  monitoring_role_arn                = length(module.gitops_resources) > 0 ? module.gitops_resources[0].monitoring_role_arn : ""
  monitoring_loki_size               = var.monitoring_loki_size
  monitoring_retention_days          = var.monitoring_retention_days
  monitoring_storage_class           = var.monitoring_storage_class
  monitoring_prometheus_storage_size = var.monitoring_prometheus_storage_size
  monitoring_node_selector           = var.monitoring_node_selector
  monitoring_tolerations             = var.monitoring_tolerations

  # Cert-Manager resources from consolidated module
  certmanager_role_arn                   = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_role_arn : ""
  certmanager_hosted_zone_id             = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_hosted_zone_id : ""
  certmanager_hosted_zone_domain         = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_hosted_zone_domain : ""
  certmanager_acme_email                 = var.certmanager_acme_email
  certmanager_certificate_domains        = var.certmanager_certificate_domains
  certmanager_enable_routes_integration  = var.certmanager_enable_routes_integration
  certmanager_ingress_enabled            = var.certmanager_ingress_enabled
  certmanager_ingress_domain             = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_ingress_domain : ""
  certmanager_ingress_visibility         = var.certmanager_ingress_visibility
  certmanager_ingress_replicas           = var.certmanager_ingress_replicas
  certmanager_ingress_route_selector     = var.certmanager_ingress_route_selector
  certmanager_ingress_namespace_selector = var.certmanager_ingress_namespace_selector
  certmanager_ingress_cert_secret_name   = length(var.certmanager_certificate_domains) > 0 ? var.certmanager_certificate_domains[0].secret_name : "custom-apps-default-cert"

  # OpenShift version for operator channel selection
  openshift_version = var.openshift_version
}

#------------------------------------------------------------------------------
# Module: Machine Pools (Optional)
#------------------------------------------------------------------------------

module "machine_pools" {
  source = "../../modules/cluster/machine-pools"
  count  = length(var.machine_pools) > 0 ? 1 : 0

  depends_on = [module.rosa_cluster]

  cluster_id = module.rosa_cluster.cluster_id

  # Pass generic machine pools list
  # See docs/MACHINE-POOLS.md for configuration examples
  machine_pools = var.machine_pools
}

#------------------------------------------------------------------------------
# Deployment Timing (Optional)
#------------------------------------------------------------------------------

module "timing" {
  source = "../../modules/utility/timing"

  enabled = var.enable_timing
  stage   = "rosa-classic-deployment"

  # Track cluster completion - timing ends when cluster is ready
  dependency_ids = [module.rosa_cluster.cluster_id]
}
