#------------------------------------------------------------------------------
# ROSA Classic Cluster Module
# Creates a ROSA Classic cluster with configurable security settings
#
# Supports both GovCloud and Commercial deployments:
# - GovCloud: FIPS required, private clusters only
# - Commercial: FIPS optional, public or private clusters
#
# Note: Private ROSA clusters use AWS PrivateLink for Red Hat SRE access.
# Public clusters allow SRE access via the public API endpoint.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

#------------------------------------------------------------------------------
# ROSA Classic Cluster
#------------------------------------------------------------------------------

resource "rhcs_cluster_rosa_classic" "this" {
  name = var.cluster_name

  # OpenShift Version and Channel Group
  # - Use channel_group = "eus" for Extended Update Support (4.14, 4.16, 4.18)
  # - Use channel_group = "stable" when upgrading through odd releases (4.15, 4.17)
  version                      = var.openshift_version
  channel_group                = var.channel_group
  upgrade_acknowledgements_for = var.upgrade_acknowledgements_for

  # Cloud Configuration
  cloud_region   = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Cluster Security Settings
  # GovCloud: FIPS required, Commercial: FIPS optional
  fips = var.fips

  # AWS PrivateLink for Red Hat SRE access (private clusters only)
  # Private clusters: SRE accesses cluster via PrivateLink endpoint
  # Public clusters: SRE accesses cluster via public API endpoint
  # Setting this to true on public clusters will cause an error
  aws_private_link = var.private_cluster

  # STS Configuration (required for both GovCloud and Commercial)
  sts = {
    oidc_config_id   = var.oidc_config_id
    role_arn         = local.installer_role_arn
    support_role_arn = local.support_role_arn
    instance_iam_roles = {
      master_role_arn = local.control_plane_role_arn
      worker_role_arn = local.worker_role_arn
    }
    operator_role_prefix = var.operator_role_prefix
  }

  # Network Configuration
  # Private cluster: only private subnets (workers run here, NAT egress handled by VPC routing)
  # Public cluster: both private and public subnets (for public ingress load balancers)
  # Note: NAT gateways in public subnets are VPC-level config, not passed to ROSA
  aws_subnet_ids     = var.private_cluster ? var.private_subnet_ids : concat(var.private_subnet_ids, var.public_subnet_ids)
  availability_zones = var.availability_zones
  machine_cidr       = var.machine_cidr
  pod_cidr           = var.pod_cidr
  service_cidr       = var.service_cidr
  host_prefix        = var.host_prefix

  # Cluster accessibility (private = no public API/ingress endpoints)
  private = var.private_cluster

  # Availability zone topology
  multi_az = var.multi_az

  # Worker Configuration
  compute_machine_type = var.compute_machine_type
  replicas             = var.worker_node_count
  worker_disk_size     = var.worker_disk_size
  default_mp_labels    = var.default_mp_labels
  autoscaling_enabled  = var.autoscaling_enabled
  min_replicas         = var.min_replicas
  max_replicas         = var.max_replicas

  # Security & Encryption
  etcd_encryption             = var.etcd_encryption
  kms_key_arn                 = var.kms_key_arn # Customer-managed KMS key for EBS encryption
  disable_workload_monitoring = var.disable_workload_monitoring
  ec2_metadata_http_tokens    = "required" # IMDSv2 only

  # Additional security groups (optional)
  # Can only be set at cluster creation time
  aws_additional_compute_security_group_ids       = length(var.aws_additional_compute_security_group_ids) > 0 ? var.aws_additional_compute_security_group_ids : null
  aws_additional_control_plane_security_group_ids = length(var.aws_additional_control_plane_security_group_ids) > 0 ? var.aws_additional_control_plane_security_group_ids : null
  aws_additional_infra_security_group_ids         = length(var.aws_additional_infra_security_group_ids) > 0 ? var.aws_additional_infra_security_group_ids : null

  # Admin User - configured via rhcs_identity_provider (htpasswd) below
  # This ensures proper IDP setup and cluster-admins group membership

  # Proxy Configuration (if provided)
  proxy = var.http_proxy != null || var.https_proxy != null ? {
    http_proxy              = var.http_proxy
    https_proxy             = var.https_proxy
    no_proxy                = var.no_proxy
    additional_trust_bundle = var.additional_trust_bundle
  } : null

  # Properties (includes rosa_creator_arn and custom tags)
  properties = merge(
    {
      rosa_creator_arn = data.aws_caller_identity.current.arn
    },
    var.tags
  )

  # Timeouts - ensure Terraform waits for operations to complete
  wait_for_create_complete   = true
  disable_waiting_in_destroy = false

  lifecycle {
    ignore_changes = [
      # Ignore version changes as upgrades should be explicit
      version,
    ]
  }
}

#------------------------------------------------------------------------------
# Admin Password Generation
#------------------------------------------------------------------------------

resource "random_password" "admin" {
  count   = var.create_admin_user ? 1 : 0
  length  = 16
  special = true
  # Password requirements for OpenShift
  override_special = "!@#$%^&*()_+-="
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

#------------------------------------------------------------------------------
# HTPasswd Identity Provider
# Creates an identity provider that allows cluster-admin login
#------------------------------------------------------------------------------

resource "rhcs_identity_provider" "htpasswd" {
  count = var.create_admin_user ? 1 : 0

  cluster = rhcs_cluster_rosa_classic.this.id
  name    = "htpasswd"

  htpasswd = {
    users = [
      {
        username = var.admin_username
        password = random_password.admin[0].result
      }
    ]
  }

  depends_on = [time_sleep.cluster_ready]
}

#------------------------------------------------------------------------------
# Grant cluster-admin role to the htpasswd user
# 
# NOTE: rhcs_group_membership is deprecated in RHCS provider but still functional.
# Future versions may require using 'oc adm groups add-users' or RBAC directly.
# Tracking: https://github.com/terraform-redhat/terraform-provider-rhcs/issues
#------------------------------------------------------------------------------

resource "rhcs_group_membership" "cluster_admin" {
  count = var.create_admin_user ? 1 : 0

  cluster = rhcs_cluster_rosa_classic.this.id
  group   = "cluster-admins"
  user    = var.admin_username

  depends_on = [rhcs_identity_provider.htpasswd]
}

#------------------------------------------------------------------------------
# Wait for cluster to be ready (create) and fully deleted (destroy)
#------------------------------------------------------------------------------

resource "time_sleep" "cluster_ready" {
  depends_on = [rhcs_cluster_rosa_classic.this]

  create_duration = "30s"
}

# Wait after cluster deletion for ROSA API to fully process
# This ensures OIDC config can be deleted without "cluster still using" errors
resource "time_sleep" "cluster_destroy_wait" {
  depends_on = [rhcs_cluster_rosa_classic.this]

  # No wait on create
  create_duration = "0s"

  # Wait 60 seconds after cluster deletion for ROSA API to release OIDC reference
  destroy_duration = "60s"

  triggers = {
    cluster_id = rhcs_cluster_rosa_classic.this.id
  }
}

#------------------------------------------------------------------------------
# Cluster Autoscaler (Optional)
# Configures cluster-wide autoscaling behavior beyond just the default machine pool.
# This controls HOW autoscaling works, while machine pool autoscaling (above)
# controls IF autoscaling is enabled and the min/max bounds.
#------------------------------------------------------------------------------

resource "rhcs_cluster_autoscaler" "this" {
  count = var.cluster_autoscaler_enabled ? 1 : 0

  cluster = rhcs_cluster_rosa_classic.this.id

  # Node provisioning timeout
  max_node_provision_time = var.autoscaler_max_node_provision_time

  # Balancing configuration
  balance_similar_node_groups   = var.autoscaler_balance_similar_node_groups
  skip_nodes_with_local_storage = var.autoscaler_skip_nodes_with_local_storage

  # Logging
  log_verbosity = var.autoscaler_log_verbosity

  # Pod configuration
  max_pod_grace_period   = var.autoscaler_max_pod_grace_period
  pod_priority_threshold = var.autoscaler_pod_priority_threshold

  # DaemonSet handling
  ignore_daemonsets_utilization = var.autoscaler_ignore_daemonsets_utilization

  # Resource limits - max nodes is inside this block
  resource_limits = {
    max_nodes_total = var.autoscaler_max_nodes_total
  }

  # Scale down configuration - use object syntax
  scale_down = {
    enabled               = var.autoscaler_scale_down_enabled
    delay_after_add       = var.autoscaler_scale_down_delay_after_add
    delay_after_delete    = var.autoscaler_scale_down_delay_after_delete
    delay_after_failure   = var.autoscaler_scale_down_delay_after_failure
    unneeded_time         = var.autoscaler_scale_down_unneeded_time
    utilization_threshold = var.autoscaler_scale_down_utilization_threshold
  }

  depends_on = [rhcs_cluster_rosa_classic.this]
}

#------------------------------------------------------------------------------
# ECR Policy Attachment
#
# Attaches ECR readonly policy to the worker role when enabled.
# This allows worker nodes to pull images from ECR repositories.
#
# Note: For Classic, this attaches to the account-level Worker role.
# The worker role is discovered from the cluster's STS configuration.
#------------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  count = var.attach_ecr_policy ? 1 : 0

  role       = "${var.account_role_prefix}-Worker-Role"
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------

locals {
  # Construct role ARNs from prefixes
  installer_role_arn     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${var.path}${var.account_role_prefix}-Installer-Role"
  support_role_arn       = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${var.path}${var.account_role_prefix}-Support-Role"
  control_plane_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${var.path}${var.account_role_prefix}-ControlPlane-Role"
  worker_role_arn        = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${var.path}${var.account_role_prefix}-Worker-Role"
}
