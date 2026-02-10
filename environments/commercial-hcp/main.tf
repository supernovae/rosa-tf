#------------------------------------------------------------------------------
# ROSA HCP (Hosted Control Plane) - Commercial AWS
#
# This environment deploys ROSA with Hosted Control Planes in AWS Commercial.
#
# Key characteristics:
# - Control plane fully managed by Red Hat (in Red Hat's AWS account)
# - Faster cluster provisioning (~15 minutes)
# - Separate billing for control plane vs machine pools
# - AWS managed IAM policies (auto-updated by AWS)
# - Private subnets only required
#
# Usage:
#   terraform init
#   terraform plan -var-file="dev.tfvars"    # Development
#   terraform plan -var-file="prod.tfvars"   # Production
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Provider Configuration
#------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "rosa-hcp"
      ManagedBy   = "terraform"
      ClusterName = var.cluster_name
    }
  }
}

provider "rhcs" {
  # Commercial endpoints
  token = var.ocm_token
  url   = "https://api.openshift.com"
}

#------------------------------------------------------------------------------
# Validation Checks
#------------------------------------------------------------------------------

# Validate GitOps configuration before any resources are created/destroyed
# This uses a null_resource with precondition to FAIL (not warn) if config is invalid
# Prevents accidental destruction of S3 buckets when install_gitops is toggled off
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

        WARNING: Setting install_gitops = false with layers enabled would
        attempt to destroy S3 buckets containing your logs and backups!
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
# AZs like us-east-1e don't support NAT Gateway or many instance types
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
# Local Variables
#------------------------------------------------------------------------------

locals {
  # Cluster type - single source of truth for all modules
  # HCP clusters have full control over openshift-monitoring namespace
  cluster_type = "hcp"

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Partition detection - derived from AWS provider, not hardcoded
  is_govcloud = local.partition == "aws-us-gov"

  # AZs that support both general availability AND required instance types
  # This filters out AZs like us-east-1e that don't support NAT Gateway
  supported_azs = sort(distinct(data.aws_ec2_instance_type_offerings.available.locations))

  # AZ count: 1 for dev (single-AZ), 3 for prod (multi-AZ)
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

  # Public subnets - needed for NAT gateway and for public clusters
  public_subnet_cidrs = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 3)
  ]

  # NAT gateway count follows AZ count: single-AZ = single NAT, multi-AZ = NAT per AZ
  use_single_nat = !var.multi_az

  # Role naming for operator roles (per-cluster)
  operator_role_prefix = var.cluster_name

  common_tags = merge(
    var.tags,
    {
      ClusterType = "rosa-hcp"
      Partition   = local.partition
    }
  )
}

#------------------------------------------------------------------------------
# Regional Availability Zone Validation
#
# ROSA HCP has regional limitations:
# - us-west-1: NOT SUPPORTED (no ETA for HCP availability)
# - Multi-AZ requires 3+ AZs
#------------------------------------------------------------------------------

check "hcp_region_support" {
  assert {
    condition     = var.aws_region != "us-west-1"
    error_message = <<-EOT
      ROSA HCP is NOT available in us-west-1.
      
      This is a platform limitation with no current ETA for availability.
      
      Options:
      1. Use us-west-2 instead (fully supported, 4 AZs)
      2. Use us-east-1 or us-east-2
      3. For us-west-1 specifically, use ROSA Classic: environments/commercial-classic/
    EOT
  }
}

check "multi_az_region_support" {
  assert {
    condition     = !var.multi_az || length(local.supported_azs) >= 3
    error_message = <<-EOT
      Multi-AZ deployment requires at least 3 availability zones.
      
      Region ${var.aws_region} has only ${length(local.supported_azs)} supported AZ(s): ${join(", ", local.supported_azs)}
      
      Options:
      1. Set multi_az = false for single-AZ deployment
      2. Use a region with 3+ AZs (e.g., us-east-1, us-west-2, eu-west-1)
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
  account_role_prefix  = var.account_role_prefix
  operator_role_prefix = local.operator_role_prefix

  # Cluster KMS configuration (for ROSA workers, etcd)
  cluster_kms_mode    = var.cluster_kms_mode
  cluster_kms_key_arn = var.cluster_kms_key_arn

  # Infrastructure KMS configuration (for jump host, CloudWatch, S3, VPN)
  infra_kms_mode    = var.infra_kms_mode
  infra_kms_key_arn = var.infra_kms_key_arn

  # HCP-specific permissions (required for worker EBS when using custom KMS)
  is_hcp_cluster             = true
  enable_hcp_etcd_encryption = var.etcd_encryption

  tags = local.common_tags
}

# Locals to simplify KMS key ARN references with strict separation
locals {
  # Cluster KMS: for ROSA workers and etcd ONLY
  # When provider_managed: null (use AWS default)
  # When create/existing: get from module
  cluster_kms_key_arn = var.cluster_kms_mode == "provider_managed" ? null : module.kms[0].cluster_kms_key_arn

  # Infrastructure KMS: for jump host, CloudWatch, S3, VPN ONLY
  # IMPORTANT: Do NOT use this for ROSA workers (strict separation)
  infra_kms_key_arn = var.infra_kms_mode == "provider_managed" ? null : module.kms[0].infra_kms_key_arn
}

#------------------------------------------------------------------------------
# VPC and Networking
#------------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/networking/vpc"

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
  #   cd environments/account-hcp && terraform apply -var-file=commercial.tfvars
  # Or: rosa create account-roles --hosted-cp --mode auto
  create_account_roles = false
  account_role_prefix  = var.account_role_prefix
  installer_role_arn   = var.installer_role_arn
  support_role_arn     = var.support_role_arn
  worker_role_arn      = var.worker_role_arn

  # Operator roles prefix (per-cluster)
  operator_role_prefix = var.cluster_name

  # KMS key ARNs for installer/support role permissions
  # Only needed when using customer-managed KMS for cluster
  # Only applies when create_account_roles = true
  # Use var.cluster_kms_mode (known at plan time) instead of computed ARN
  enable_kms_permissions = var.cluster_kms_mode != "provider_managed"
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
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  vpc_cidr             = var.vpc_cidr

  tags = local.common_tags

  depends_on = [module.vpc]
}

#------------------------------------------------------------------------------
# ROSA HCP Cluster
#------------------------------------------------------------------------------

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
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr

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

module "rosa_cluster" {
  source = "../../modules/cluster/rosa-hcp"

  cluster_name   = var.cluster_name
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  creator_arn    = data.aws_caller_identity.current.arn

  # Network configuration
  # Private clusters: only private subnets
  # Public clusters: requires both private and public subnets (min 2 AZs)
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = var.private_cluster ? [] : module.vpc.public_subnet_ids
  availability_zones = local.availability_zones
  machine_cidr       = var.vpc_cidr

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

  # Partition detection (affects billing account handling)
  is_govcloud = local.is_govcloud

  # Security configuration
  private_cluster = var.private_cluster
  zero_egress     = var.zero_egress

  # Additional security groups (can only be set at cluster creation time)
  aws_additional_compute_security_group_ids = module.additional_security_groups.compute_security_group_ids

  # Cluster KMS encryption (uses cluster_kms_key_arn ONLY - strict separation):
  # - provider_managed: null (uses AWS managed aws/ebs key - encryption at rest enabled)
  # - create/existing: uses customer-managed KMS key
  etcd_encryption  = var.etcd_encryption && local.cluster_kms_key_arn != null
  etcd_kms_key_arn = var.etcd_encryption ? local.cluster_kms_key_arn : null
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
    vpc_id       = module.vpc.vpc_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      VPC_ID="${self.triggers.vpc_id}"
      CLUSTER_NAME="${self.triggers.cluster_name}"
      
      echo "=== VPC Cleanup: Waiting for AWS to clean up cluster resources ==="
      echo "VPC: $VPC_ID"
      echo "Cluster: $CLUSTER_NAME"
      
      # Wait for initial AWS cleanup (load balancers, etc.)
      echo "Waiting 2 minutes for initial AWS cleanup..."
      sleep 120
      
      # Clean up orphaned ENIs (created by load balancers, Lambda, etc.)
      echo "Checking for orphaned ENIs in VPC..."
      for i in 1 2 3; do
        ENIS=$(aws ec2 describe-network-interfaces \
          --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
          --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null || echo "")
        
        if [ -n "$ENIS" ] && [ "$ENIS" != "None" ]; then
          echo "Found orphaned ENIs: $ENIS"
          for ENI in $ENIS; do
            echo "Deleting ENI: $ENI"
            aws ec2 delete-network-interface --network-interface-id "$ENI" 2>/dev/null || true
          done
          sleep 10
        else
          echo "No orphaned ENIs found."
          break
        fi
      done
      
      # Clean up orphaned security groups (non-default, created by ROSA/ELB)
      echo "Checking for orphaned security groups in VPC..."
      for i in 1 2 3; do
        # Get non-default security groups that might be orphaned
        SGS=$(aws ec2 describe-security-groups \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || echo "")
        
        if [ -n "$SGS" ] && [ "$SGS" != "None" ]; then
          echo "Found security groups: $SGS"
          for SG in $SGS; do
            # Check if SG has any network interfaces using it
            IN_USE=$(aws ec2 describe-network-interfaces \
              --filters "Name=group-id,Values=$SG" \
              --query 'NetworkInterfaces[0].NetworkInterfaceId' --output text 2>/dev/null || echo "None")
            
            if [ "$IN_USE" = "None" ] || [ -z "$IN_USE" ]; then
              echo "Attempting to delete unused SG: $SG"
              aws ec2 delete-security-group --group-id "$SG" 2>/dev/null || true
            else
              echo "SG $SG still in use by ENI: $IN_USE"
            fi
          done
          sleep 10
        else
          echo "No non-default security groups found."
          break
        fi
      done
      
      echo "=== VPC Cleanup complete. Proceeding with infrastructure deletion. ==="
    EOT
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
  subnet_id         = module.vpc.private_subnet_ids[0]

  # Pass generic machine pools list
  # See docs/MACHINE-POOLS.md for configuration examples
  machine_pools = var.machine_pools

  tags = local.common_tags

  depends_on = [module.rosa_cluster]
}

#------------------------------------------------------------------------------
# Jump Host (Optional - for private cluster access)
#------------------------------------------------------------------------------

module "jumphost" {
  source = "../../modules/networking/jumphost"
  count  = var.create_jumphost ? 1 : 0

  # Destroy ordering: jumphost must be destroyed BEFORE VPC (ENI cleanup)
  depends_on = [module.rosa_cluster, module.vpc]

  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_id           = module.vpc.private_subnet_ids[0]
  instance_type       = var.jumphost_instance_type
  ami_id              = var.jumphost_ami_id
  cluster_api_url     = module.rosa_cluster.api_url
  cluster_console_url = module.rosa_cluster.console_url
  cluster_domain      = module.rosa_cluster.domain

  # Infrastructure KMS key for jump host encryption (null = use AWS default)
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
  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = var.vpc_cidr

  # Single subnet for cost (add more for HA)
  subnet_ids = [module.vpc.private_subnet_ids[0]]

  client_cidr_block     = var.vpn_client_cidr_block
  split_tunnel          = var.vpn_split_tunnel
  session_timeout_hours = var.vpn_session_timeout_hours

  # Infrastructure KMS for VPN log encryption (null = use AWS default)
  # Uses infra_kms_key_arn - NOT cluster KMS (strict separation)
  kms_key_arn = local.infra_kms_key_arn

  tags = local.common_tags
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

  # Monitoring config (for AWS resource creation)
  monitoring_retention_days          = var.monitoring_retention_days
  monitoring_prometheus_storage_size = var.monitoring_prometheus_storage_size
  monitoring_storage_class           = var.monitoring_storage_class
  is_govcloud                        = local.is_govcloud
  openshift_version                  = var.openshift_version

  # Cert-Manager config (for AWS resource creation)
  certmanager_hosted_zone_id     = var.certmanager_hosted_zone_id
  certmanager_hosted_zone_domain = var.certmanager_hosted_zone_domain
  certmanager_create_hosted_zone = var.certmanager_create_hosted_zone

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Module: Cluster Authentication (for GitOps)
#
# Retrieves an OAuth token for authenticating to the cluster using the htpasswd
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
# Uses curl-based API calls with OAuth token from cluster_auth module.
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

  cluster_name    = var.cluster_name
  cluster_api_url = module.rosa_cluster.api_url
  cluster_token   = length(module.cluster_auth) > 0 ? module.cluster_auth[0].token : ""
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
  certmanager_role_arn                  = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_role_arn : ""
  certmanager_hosted_zone_id            = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_hosted_zone_id : ""
  certmanager_hosted_zone_domain        = length(module.gitops_resources) > 0 ? module.gitops_resources[0].certmanager_hosted_zone_domain : ""
  certmanager_acme_email                = var.certmanager_acme_email
  certmanager_certificate_domains       = var.certmanager_certificate_domains
  certmanager_enable_routes_integration = var.certmanager_enable_routes_integration

  # OpenShift version for operator channel selection
  openshift_version = var.openshift_version
}

#------------------------------------------------------------------------------
# Deployment Timing (Optional)
#------------------------------------------------------------------------------

module "timing" {
  source = "../../modules/utility/timing"

  enabled = var.enable_timing
  stage   = "rosa-hcp-deployment"

  # Track cluster completion - timing ends when cluster is ready
  dependency_ids = [module.rosa_cluster.cluster_id]
}
