#------------------------------------------------------------------------------
# ROSA HCP (Hosted Control Plane) - AWS GovCloud
#
# This environment deploys ROSA with Hosted Control Planes in AWS GovCloud.
#
# GovCloud Requirements (enforced):
# - FIPS mode: ENABLED (mandatory)
# - Cluster access: PRIVATE only (mandatory)
# - KMS encryption: REQUIRED (mandatory)
# - API endpoint: api.openshiftusgov.com
#
# Two-phase deployment:
#   Phase 1 (cluster):  terraform apply -var-file="cluster-dev.tfvars"
#   Phase 2 (layers):   terraform apply -var-file="cluster-dev.tfvars" -var-file="gitops-dev.tfvars"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Provider Configuration
#------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "rosa-hcp-govcloud"
      ManagedBy   = "terraform"
      ClusterName = var.cluster_name
      Compliance  = "fedramp-high"
    }
  }

  # ROSA installer manages kubernetes.io/cluster/* tags on subnets and
  # security groups. Ignore them so Phase 2 (and subsequent) applies
  # don't produce unnecessary modifications.
  ignore_tags {
    key_prefixes = ["kubernetes.io/cluster/"]
  }
}

provider "rhcs" {
  # GovCloud endpoints (FedRAMP)
  # IMPORTANT: Do NOT set RHCS_TOKEN or RHCS_URL environment variables
  # as they can override provider settings and cause authentication failures.
  token     = var.ocm_token
  url       = "https://api.openshiftusgov.com"
  token_url = "https://sso.openshiftusgov.com/realms/redhat-external/protocol/openid-connect/token"
  client_id = "console-dot"
}

# Kubernetes provider for native resource management (GitOps layers).
#
# Authentication priority:
#   1. gitops_cluster_token (SA token from previous bootstrap) -- no OAuth needed
#   2. cluster_auth module (OAuth bootstrap) -- first run only
#
# For GovCloud private clusters: VPN connectivity required for API access.
provider "kubernetes" {
  host     = local.effective_k8s_host
  token    = local.effective_k8s_token
  insecure = true

  # Suppress kubeconfig file loading -- use explicit host/token only
  config_paths   = []
  config_context = ""
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

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Filter AZs that support the instance types we need (proxy for NAT Gateway support)
# Some AZs don't support NAT Gateway or many instance types
data "aws_ec2_instance_type_offerings" "available" {
  filter {
    name   = "instance-type"
    values = ["m5.xlarge"] # Standard ROSA worker type
  }

  filter {
    name   = "location"
    values = data.aws_availability_zones.available.names
  }

  location_type = "availability-zone"
}

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
# Local Variables
#------------------------------------------------------------------------------

locals {
  # Cluster type - single source of truth for all modules
  # HCP clusters have full control over openshift-monitoring namespace
  cluster_type = "hcp"

  # Kubernetes provider host: cluster API when gitops enabled, dummy otherwise.
  # With two-phase deployment, Phase 1 always has install_gitops=false (localhost)
  # and Phase 2 always has the cluster in state (api_url is known).
  effective_k8s_host = var.install_gitops ? module.rosa_cluster.api_url : "https://localhost"

  # Kubernetes provider token: SA token (steady state) or OAuth token (bootstrap)
  # Priority: gitops_cluster_token (from previous run) > cluster_auth OAuth > empty
  effective_k8s_token = (
    var.gitops_cluster_token != null
    ? var.gitops_cluster_token
    : try(module.cluster_auth[0].token, "")
  )

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Verify we're in GovCloud
  is_govcloud = local.partition == "aws-us-gov"

  # AZs that support both general availability AND required instance types
  # This filters out AZs that don't support NAT Gateway
  supported_azs = sort(distinct(data.aws_ec2_instance_type_offerings.available.locations))

  # HCP uses only private subnets (control plane in Red Hat's account)
  az_count = var.multi_az ? 3 : 1

  availability_zones = var.availability_zones != null ? var.availability_zones : slice(
    local.supported_azs,
    0,
    min(local.az_count, length(local.supported_azs))
  )

  # Network configuration
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i)
  ]

  # Public subnets for NAT gateway and bastion access
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

  # Role naming for operator roles (per-cluster)
  operator_role_prefix = var.cluster_name

  common_tags = merge(
    var.tags,
    {
      ClusterType = "rosa-hcp"
      Partition   = local.partition
      FIPSMode    = "enabled"
    }
  )
}

#------------------------------------------------------------------------------
# Partition Validation
#------------------------------------------------------------------------------

check "govcloud_partition" {
  assert {
    condition     = local.is_govcloud
    error_message = <<-EOT
      This environment is designed for AWS GovCloud (aws-us-gov partition).
      Current partition: ${local.partition}
      
      For commercial AWS, use: environments/commercial-hcp/
    EOT
  }
}

#------------------------------------------------------------------------------
# KMS Keys (MANDATORY for GovCloud - FedRAMP compliance)
#
# Two separate keys with STRICT SEPARATION for blast radius containment:
# - Cluster KMS: ROSA workers and etcd ONLY (Red Hat expected policy)
# - Infrastructure KMS: Jump host, CloudWatch, S3/OADP, VPN ONLY
#
# GovCloud does NOT support "provider_managed" by default.
# FedRAMP SC-12/SC-13 requires customer control over cryptographic keys.
#------------------------------------------------------------------------------

module "kms" {
  source = "../../modules/security/kms"

  # Only create if at least one key is in "create" mode
  count = (var.cluster_kms_mode == "create" || var.infra_kms_mode == "create") ? 1 : 0

  cluster_name         = var.cluster_name
  account_role_prefix  = var.account_role_prefix
  operator_role_prefix = local.operator_role_prefix

  # Cluster KMS configuration (for ROSA workers, etcd)
  cluster_kms_mode    = var.cluster_kms_mode
  cluster_kms_key_arn = var.cluster_kms_key_arn

  # Infrastructure KMS configuration (for jump host, CloudWatch, S3, VPN)
  infra_kms_mode    = var.infra_kms_mode
  infra_kms_key_arn = var.infra_kms_key_arn

  # HCP cluster - enables EC2/Auto Scaling/CAPA permissions for worker EBS
  is_hcp_cluster = true

  # Enable HCP-specific etcd encryption policy (mandatory for GovCloud)
  enable_hcp_etcd_encryption = true

  kms_key_deletion_window = var.kms_key_deletion_window
  tags                    = local.common_tags
}

# Locals to simplify KMS key ARN references with strict separation
locals {
  # Cluster KMS: for ROSA workers and etcd ONLY
  cluster_kms_key_arn = var.cluster_kms_mode == "create" ? module.kms[0].cluster_kms_key_arn : var.cluster_kms_key_arn

  # Infrastructure KMS: for jump host, CloudWatch, S3, VPN ONLY
  # IMPORTANT: Do NOT use this for ROSA workers (strict separation)
  infra_kms_key_arn = var.infra_kms_mode == "create" ? module.kms[0].infra_kms_key_arn : var.infra_kms_key_arn
}

#------------------------------------------------------------------------------
# VPC and Networking
#------------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/networking/vpc"
  count  = var.existing_vpc_id == null ? 1 : 0

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  private_subnet_cidrs = local.private_subnet_cidrs
  public_subnet_cidrs  = local.public_subnet_cidrs

  # Egress configuration
  # Zero-egress clusters have no NAT/IGW - use egress_type = "none"
  egress_type        = var.zero_egress ? "none" : var.egress_type
  single_nat_gateway = local.use_single_nat

  transit_gateway_id         = var.transit_gateway_id
  transit_gateway_route_cidr = var.transit_gateway_route_cidr

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# IAM Roles (HCP uses AWS Managed Policies)
#
# Account roles (shared) - can be created here or discovered from account layer
# Operator roles (per-cluster) - always created per cluster
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

module "iam_roles" {
  source = "../../modules/security/iam/rosa-hcp"

  cluster_name = var.cluster_name

  # Account roles - HCP uses shared account-level roles
  # Roles must exist before deploying. Create via:
  #   cd environments/account-hcp && terraform apply -var-file=govcloud.tfvars
  # Or: rosa create account-roles --hosted-cp --mode auto
  create_account_roles = false
  account_role_prefix  = var.account_role_prefix
  installer_role_arn   = var.installer_role_arn
  support_role_arn     = var.support_role_arn
  worker_role_arn      = var.worker_role_arn

  # Operator roles prefix (per-cluster)
  operator_role_prefix = var.cluster_name

  # KMS key ARN for installer/support role permissions
  # Only cluster KMS is needed for installer role (ROSA resources)
  # Only applies when create_account_roles = true
  # GovCloud requires customer-managed KMS, so always enable
  enable_kms_permissions = true # GovCloud: KMS is mandatory
  kms_key_arns           = local.cluster_kms_key_arn != null ? [local.cluster_kms_key_arn] : []

  # ECR policy for container image pulls
  # Only applies when create_account_roles = true
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

  depends_on = [module.kms]
}

#------------------------------------------------------------------------------
# ECR Repository (Optional)
# Private container registry for custom images or operator mirroring
#------------------------------------------------------------------------------

module "ecr" {
  source = "../../modules/registry/ecr"
  count  = var.create_ecr ? 1 : 0

  cluster_name    = var.cluster_name
  repository_name = var.ecr_repository_name
  kms_key_arn     = local.infra_kms_key_arn

  # Lifecycle management - when true, ECR survives cluster destroy
  prevent_destroy = var.ecr_prevent_destroy

  # Generate IDMS config for zero-egress clusters
  generate_idms = var.zero_egress

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
  existing_compute_security_group_ids = var.existing_compute_security_group_ids

  # Custom rules
  compute_ingress_rules = var.compute_security_group_rules.ingress
  compute_egress_rules  = var.compute_security_group_rules.egress

  tags = local.common_tags

  depends_on = [module.vpc]
}

#------------------------------------------------------------------------------
# ROSA HCP Cluster
#------------------------------------------------------------------------------

module "rosa_cluster" {
  source = "../../modules/cluster/rosa-hcp"

  cluster_name   = var.cluster_name
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  creator_arn    = data.aws_caller_identity.current.arn

  # Network configuration - HCP only needs private subnets
  private_subnet_ids = local.effective_private_subnet_ids
  availability_zones = local.effective_availability_zones
  machine_cidr       = local.effective_vpc_cidr

  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr
  host_prefix  = var.host_prefix

  # IAM configuration
  oidc_config_id       = module.iam_roles.oidc_config_id
  installer_role_arn   = module.iam_roles.installer_role_arn
  support_role_arn     = module.iam_roles.support_role_arn
  worker_role_arn      = module.iam_roles.worker_role_arn
  operator_role_prefix = var.cluster_name

  # OpenShift configuration
  openshift_version            = var.openshift_version
  channel_group                = var.channel_group
  upgrade_acknowledgements_for = var.upgrade_acknowledgements_for
  compute_machine_type         = var.compute_machine_type
  replicas                     = var.worker_node_count

  # GovCloud flag (affects billing account handling)
  is_govcloud = true

  # GovCloud Security (MANDATORY - not configurable)
  private_cluster = true # Always private in GovCloud
  zero_egress     = var.zero_egress
  etcd_encryption = true # Always encrypted

  # Additional security groups (can only be set at cluster creation time)
  aws_additional_compute_security_group_ids = module.additional_security_groups.compute_security_group_ids

  # Cluster KMS encryption (MANDATORY for GovCloud)
  # Uses cluster_kms_key_arn ONLY (strict separation from infrastructure)
  etcd_kms_key_arn = local.cluster_kms_key_arn
  ebs_kms_key_arn  = local.cluster_kms_key_arn

  # Admin user
  create_admin_user = var.create_admin_user
  admin_username    = var.admin_username

  # External authentication (HCP only)
  # Replaces built-in OAuth with external OIDC provider
  external_auth_providers_enabled = var.external_auth_providers_enabled

  # Version drift check
  skip_version_drift_check = var.skip_version_drift_check

  # Cluster autoscaler (controls HOW autoscaling works)
  # Machine pools also need autoscaling enabled (controls IF autoscaling happens)
  cluster_autoscaler_enabled         = var.cluster_autoscaler_enabled
  autoscaler_max_nodes_total         = var.autoscaler_max_nodes_total
  autoscaler_max_node_provision_time = var.autoscaler_max_node_provision_time
  autoscaler_max_pod_grace_period    = var.autoscaler_max_pod_grace_period
  autoscaler_pod_priority_threshold  = var.autoscaler_pod_priority_threshold

  tags = local.common_tags

  depends_on = [
    module.iam_roles,
    module.vpc,
    module.kms,
    module.additional_security_groups,
    null_resource.wait_for_cluster_destroy,
  ]
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
# Machine Pools (HCP-specific)
#------------------------------------------------------------------------------

module "machine_pools" {
  source = "../../modules/cluster/machine-pools-hcp"
  count  = length(var.machine_pools) > 0 ? 1 : 0

  cluster_id        = module.rosa_cluster.cluster_id
  openshift_version = coalesce(var.machine_pool_version, var.openshift_version)
  subnet_id         = local.effective_private_subnet_ids[0]

  # Pass generic machine pools list
  # See docs/MACHINE-POOLS.md for configuration examples
  machine_pools = var.machine_pools

  tags = local.common_tags

  depends_on = [module.rosa_cluster]
}

#------------------------------------------------------------------------------
# Jump Host (Required for private cluster access)
#------------------------------------------------------------------------------

module "jumphost" {
  source = "../../modules/networking/jumphost"
  count  = var.create_jumphost ? 1 : 0

  # Destroy ordering: jumphost must be destroyed BEFORE VPC (ENI cleanup)
  depends_on = [module.rosa_cluster, module.vpc]

  cluster_name        = var.cluster_name
  vpc_id              = local.effective_vpc_id
  subnet_id           = local.effective_private_subnet_ids[0]
  instance_type       = var.jumphost_instance_type
  ami_id              = var.jumphost_ami_id
  cluster_api_url     = module.rosa_cluster.api_url
  cluster_console_url = module.rosa_cluster.console_url
  cluster_domain      = module.rosa_cluster.domain

  # Infrastructure KMS key for jump host encryption
  # Uses infra_kms_key_arn - NOT cluster KMS (strict separation)
  kms_key_arn = local.infra_kms_key_arn

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Client VPN (Optional - for private cluster access)
#------------------------------------------------------------------------------

module "client_vpn" {
  source = "../../modules/networking/client-vpn"
  count  = var.create_client_vpn ? 1 : 0

  # Destroy ordering: VPN must be destroyed BEFORE VPC (ENI/SG cleanup)
  depends_on = [module.rosa_cluster, module.vpc]

  cluster_name   = var.cluster_name
  cluster_domain = module.rosa_cluster.domain
  vpc_id         = local.effective_vpc_id
  vpc_cidr       = local.effective_vpc_cidr

  # Single subnet for cost (add more for HA)
  subnet_ids = [local.effective_private_subnet_ids[0]]

  client_cidr_block     = var.vpn_client_cidr_block
  split_tunnel          = var.vpn_split_tunnel
  session_timeout_hours = var.vpn_session_timeout_hours

  # Infrastructure KMS for VPN log encryption
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

# Validate: cert-manager requires outbound internet (incompatible with zero-egress)
resource "terraform_data" "validate_certmanager_egress" {
  count = var.enable_layer_certmanager ? 1 : 0

  lifecycle {
    precondition {
      condition     = !var.zero_egress
      error_message = "Cert-Manager DNS01 challenge requires outbound internet access and cannot be used with zero_egress = true. Use manually provided certificates instead."
    }
  }
}

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
  is_govcloud                        = true
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
# Retrieves an OAuth token for authenticating to the cluster using the htpasswd
# identity provider credentials created with the cluster.
#
# IMPORTANT: This requires the htpasswd IDP to be present on the cluster.
# For GovCloud, clusters are always private - ensure VPN/jump host connectivity.
# See modules/gitops-layers/operator/README.md for Day 0 vs Day 2 guidance.
#------------------------------------------------------------------------------

module "cluster_auth" {
  source = "../../modules/utility/cluster-auth"
  count  = var.install_gitops ? 1 : 0

  depends_on = [module.rosa_cluster]

  enabled       = var.install_gitops
  api_url       = module.rosa_cluster.api_url
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
# NOTE: GovCloud clusters are ALWAYS private. GitOps will only succeed if:
# 1. Terraform runner has VPN or direct network access to cluster
# 2. cluster_auth module obtained a valid token
# See: docs/OPERATIONS.md for two-phase deployment pattern.
#------------------------------------------------------------------------------

module "gitops" {
  source = "../../modules/gitops-layers/operator"
  count  = var.install_gitops ? 1 : 0

  depends_on = [
    module.rosa_cluster,
    module.cluster_auth,
    module.gitops_resources
  ]

  cluster_name    = var.cluster_name
  cluster_api_url = module.rosa_cluster.api_url
  cluster_token   = length(module.cluster_auth) > 0 ? module.cluster_auth[0].token : ""
  terraform_sa_name      = var.terraform_sa_name
  terraform_sa_namespace = var.terraform_sa_namespace
  skip_k8s_destroy       = var.skip_k8s_destroy
  cluster_type    = local.cluster_type
  aws_region      = var.aws_region
  aws_account_id  = data.aws_caller_identity.current.account_id

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
# Deployment Timing (Optional)
#------------------------------------------------------------------------------

module "timing" {
  source = "../../modules/utility/timing"

  enabled = var.enable_timing
  stage   = "rosa-hcp-govcloud-deployment"

  # Track cluster completion - timing ends when cluster is ready
  dependency_ids = [module.rosa_cluster.cluster_id]
}
