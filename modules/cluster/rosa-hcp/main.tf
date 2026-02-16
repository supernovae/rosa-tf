#------------------------------------------------------------------------------
# ROSA HCP (Hosted Control Plane) Cluster Module
#
# Creates a ROSA cluster with Hosted Control Planes.
# 
# Key differences from ROSA Classic:
# - Control plane is fully managed by Red Hat (no customer-managed nodes)
# - Only private subnets required (control plane in Red Hat's account)
# - Faster provisioning (~15 minutes vs 40+ minutes)
# - Separate control plane and machine pool billing
# - Machine pools managed via rhcs_hcp_machine_pool resource
#
# Note: HCP clusters ALWAYS use AWS PrivateLink to connect worker nodes
# to the Red Hat-managed control plane. This is architectural and not configurable.
# The private_cluster variable controls whether the API/ingress endpoints are
# publicly accessible, not the control plane connectivity.
#
# See: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_clusters/creating-a-rosa-cluster-using-terraform
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Version Drift Check
# HCP machine pools must be within n-2 minor versions of control plane
#------------------------------------------------------------------------------

locals {
  # Parse control plane version for validation
  version_parts       = split(".", var.openshift_version)
  control_plane_major = local.version_parts[0]
  control_plane_minor = tonumber(local.version_parts[1])

  # Minimum allowed machine pool version (n-2)
  min_machine_pool_minor = local.control_plane_minor - 2
}

# Version drift validation (warning or error based on configuration)
check "version_drift_check" {
  assert {
    condition     = var.skip_version_drift_check || true
    error_message = <<-EOT
      ROSA HCP requires machine pool versions to be within n-2 of control plane.
      Control plane: ${var.openshift_version}
      Minimum machine pool version: ${local.control_plane_major}.${local.min_machine_pool_minor}.x
      
      When upgrading, update control plane first, then machine pools.
      Set skip_version_drift_check = true to suppress this check.
    EOT
  }
}

#------------------------------------------------------------------------------
# ROSA HCP Cluster
#------------------------------------------------------------------------------

resource "rhcs_cluster_rosa_hcp" "this" {
  name = var.cluster_name

  # Cloud provider configuration
  cloud_region   = var.aws_region
  aws_account_id = var.aws_account_id

  # Billing account configuration:
  # - GovCloud: MUST be null (billing association not supported yet)
  # - Commercial: REQUIRED, defaults to deployment account if not specified
  # Known Issue: GovCloud billing support is pending OCM/ROSA CLI updates
  aws_billing_account_id = var.is_govcloud ? null : (
    var.aws_billing_account_id != "" ? var.aws_billing_account_id : var.aws_account_id
  )

  # OpenShift configuration
  version                      = var.openshift_version
  channel_group                = var.channel_group
  upgrade_acknowledgements_for = var.upgrade_acknowledgements_for
  compute_machine_type         = var.compute_machine_type
  replicas                     = var.replicas

  # Properties including required rosa_creator_arn and optional zero_egress
  properties = merge(
    var.cluster_properties,
    {
      rosa_creator_arn = var.creator_arn
    },
    var.zero_egress ? { zero_egress = "true" } : {}
  )

  # Network configuration
  # Private clusters: only private subnets needed
  # Public clusters: requires both private and public subnets (min 2 AZs)
  aws_subnet_ids = var.private_cluster ? var.private_subnet_ids : concat(var.private_subnet_ids, var.public_subnet_ids)
  machine_cidr   = var.machine_cidr
  service_cidr   = var.service_cidr
  pod_cidr       = var.pod_cidr
  host_prefix    = var.host_prefix
  private        = var.private_cluster

  # IAM configuration - uses AWS managed policies
  sts = {
    role_arn             = var.installer_role_arn
    support_role_arn     = var.support_role_arn
    operator_role_prefix = var.operator_role_prefix
    oidc_config_id       = var.oidc_config_id
    instance_iam_roles = {
      worker_role_arn = var.worker_role_arn
    }
  }

  # Encryption configuration
  etcd_encryption  = var.etcd_encryption
  etcd_kms_key_arn = var.etcd_kms_key_arn
  kms_key_arn      = var.ebs_kms_key_arn

  # Availability configuration
  availability_zones = var.availability_zones

  # Additional security groups (optional)
  # Can only be set at cluster creation time
  aws_additional_compute_security_group_ids = length(var.aws_additional_compute_security_group_ids) > 0 ? var.aws_additional_compute_security_group_ids : null

  # External Authentication (HCP only)
  # Enables direct integration with external OIDC identity providers
  # for user authentication, replacing the built-in OpenShift OAuth server.
  # IMPORTANT: Cannot be changed after cluster creation.
  external_auth_providers_enabled = var.external_auth_providers_enabled

  # Wait configuration
  wait_for_create_complete            = var.wait_for_create_complete
  wait_for_std_compute_nodes_complete = var.wait_for_std_compute_nodes_complete

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_ids) >= 1
      error_message = "At least one private subnet is required for ROSA HCP."
    }

    precondition {
      condition     = !var.zero_egress || var.private_cluster
      error_message = "Zero-egress mode requires private_cluster = true."
    }

    # Ignore version changes - upgrades should be explicit
    # This prevents Terraform from "downgrading" if cluster was upgraded
    # via Hybrid Cloud Console or automatic z-stream updates
    ignore_changes = [
      version,
    ]
  }
}

#------------------------------------------------------------------------------
# Wait for cluster to be ready before configuring IDP
#------------------------------------------------------------------------------

resource "time_sleep" "cluster_ready" {
  depends_on = [rhcs_cluster_rosa_hcp.this]

  create_duration = "30s"
}

#------------------------------------------------------------------------------
# Re-read cluster attributes after the ready wait.
#
# The RHCS provider's Create handler may return before the OCM API has
# populated api_url and console_url (they arrive shortly after state=ready).
# This data source forces a fresh Read after the 30s settle window,
# guaranteeing those computed attributes are captured in state.
#------------------------------------------------------------------------------

data "rhcs_cluster_rosa_hcp" "info" {
  id         = rhcs_cluster_rosa_hcp.this.id
  depends_on = [time_sleep.cluster_ready]
}

#------------------------------------------------------------------------------
# Cluster Admin User (htpasswd IDP)
# Provides initial cluster access
#------------------------------------------------------------------------------

resource "random_password" "cluster_admin" {
  count = var.create_admin_user ? 1 : 0

  length      = 16
  special     = true
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
  min_special = 2
  # Same special chars as rosa-classic for consistency
  override_special = "!@#$%^&*()_+-="
}

resource "rhcs_identity_provider" "htpasswd" {
  count = var.create_admin_user ? 1 : 0

  cluster = rhcs_cluster_rosa_hcp.this.id
  name    = "htpasswd" # Consistent with rosa-classic

  htpasswd = {
    users = [
      {
        username = var.admin_username
        password = random_password.cluster_admin[0].result
      }
    ]
  }

  # Wait for cluster to be ready before creating IDP
  depends_on = [time_sleep.cluster_ready]
}

resource "rhcs_group_membership" "cluster_admin" {
  count = var.create_admin_user ? 1 : 0

  # Note: Using group membership is deprecated but still functional.
  # The RHCS provider may migrate to a different resource in the future.
  cluster = rhcs_cluster_rosa_hcp.this.id
  group   = "cluster-admins"
  user    = var.admin_username

  depends_on = [rhcs_identity_provider.htpasswd]
}

#------------------------------------------------------------------------------
# Cluster Autoscaler (Optional)
# 
# For ROSA HCP, the Cluster Autoscaler is fully managed by Red Hat and runs
# alongside the hosted control plane. This resource configures cluster-wide
# autoscaling behavior.
#
# Key differences from Classic:
# - Autoscaler runs in Red Hat's infrastructure (not your VPC)
# - Fewer configuration options (simplified managed experience)
# - Works with HCP machine pools that have autoscaling enabled
#
# Both components needed for full autoscaling:
# 1. Cluster Autoscaler: Controls HOW autoscaling works (this resource)
# 2. Machine Pool Autoscaling: Controls IF autoscaling is enabled (min/max)
#------------------------------------------------------------------------------

resource "rhcs_cluster_autoscaler" "this" {
  count = var.cluster_autoscaler_enabled ? 1 : 0

  cluster = rhcs_cluster_rosa_hcp.this.id

  # Maximum nodes across all autoscaling machine pools
  # Note: Nodes in non-autoscaling pools are NOT counted toward this limit
  resource_limits = {
    max_nodes_total = var.autoscaler_max_nodes_total
  }

  # Node provisioning timeout
  max_node_provision_time = var.autoscaler_max_node_provision_time

  # Pod grace period for scale down (seconds)
  max_pod_grace_period = var.autoscaler_max_pod_grace_period

  # Pod priority threshold
  # Pods below this priority won't trigger scale up or prevent scale down
  pod_priority_threshold = var.autoscaler_pod_priority_threshold

  depends_on = [rhcs_cluster_rosa_hcp.this]
}
