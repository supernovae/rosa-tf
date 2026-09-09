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
# ROSA HCP Cluster
#------------------------------------------------------------------------------

resource "rhcs_cluster_rosa_hcp" "this" {
  audit_log_arn                           = var.cluster_options.audit_log_arn
  aws_additional_allowed_principals       = var.cluster_options.aws_additional_allowed_principals
  base_dns_domain                         = var.cluster_options.base_dns_domain
  destroy_timeout                         = var.cluster_options.destroy_timeout
  domain_prefix                           = var.cluster_options.domain_prefix
  log_forwarders_at_cluster_creation      = var.cluster_options.log_forwarders_at_cluster_creation
  max_hcp_cluster_wait_timeout_in_minutes = var.cluster_options.max_hcp_cluster_wait_timeout_in_minutes
  max_machinepool_wait_timeout_in_minutes = var.cluster_options.max_machinepool_wait_timeout_in_minutes
  proxy                                   = var.cluster_options.proxy
  registry_config                         = var.cluster_options.registry_config
  shared_vpc                              = var.cluster_options.shared_vpc
  spot_termination_queue_url              = var.cluster_options.spot_termination_queue_url
  worker_disk_size                        = var.cluster_options.worker_disk_size
  autoscaling_enabled                     = var.cluster_options.autoscaling_enabled
  min_replicas                            = var.cluster_options.min_replicas
  max_replicas                            = var.cluster_options.max_replicas
  channel                                 = var.cluster_options.channel
  tags                                    = var.tags

  ec2_metadata_http_tokens = "required"
  delete_protection        = var.cluster_delete_protection
  # Native RHCS bootstrap creates the htpasswd user and grants admin access.
  admin_credentials = var.create_admin_user ? {
    username = var.admin_username
    password = random_password.cluster_admin[0].result
  } : null

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
  channel_group                = var.cluster_options.channel == null ? var.channel_group : null
  upgrade_acknowledgements_for = var.upgrade_acknowledgements_for
  compute_machine_type         = var.compute_machine_type
  replicas                     = coalesce(var.cluster_options.autoscaling_enabled, false) ? null : var.replicas

  # Properties including required rosa_creator_arn and optional zero_egress
  properties = merge(
    {
      rosa_creator_arn = var.creator_arn
    },
    var.cluster_options.properties,
    var.zero_egress ? { zero_egress = "true" } : {}
  )

  # AutoNode (Karpenter) - enables native node autoscaling via Karpenter
  auto_node = var.autonode_role_arn != null ? {
    mode     = "enabled"
    role_arn = var.autonode_role_arn
  } : null

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
    trust_policy_external_id = var.cluster_options.trust_policy_external_id
    role_arn                 = var.installer_role_arn
    support_role_arn         = var.support_role_arn
    operator_role_prefix     = var.operator_role_prefix
    oidc_config_id           = var.oidc_config_id
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

  # FIPS mode (immutable after creation)
  fips = var.fips

  # Wait configuration
  wait_for_create_complete            = var.wait_for_create_complete
  wait_for_std_compute_nodes_complete = var.wait_for_std_compute_nodes_complete

  disable_waiting_in_destroy = false
  no_cni                     = false

  lifecycle {
    precondition {
      condition     = var.autonode_role_arn == null ? true : tonumber(split(".", var.openshift_version)[1]) >= 22
      error_message = "The documented Red Hat build of Karpenter path requires OpenShift 4.22 or later."
    }
    precondition {
      condition     = var.autonode_role_arn == null || var.wait_for_create_complete
      error_message = "AutoNode requires native create completion waiting for post-create activation."
    }
    precondition {
      condition     = !var.external_auth_providers_enabled || !var.create_admin_user
      error_message = "External authentication and htpasswd admin bootstrap cannot be combined."
    }
    precondition {
      condition     = length(var.private_subnet_ids) >= 1
      error_message = "At least one private subnet is required for ROSA HCP."
    }

    precondition {
      condition     = !var.zero_egress || var.private_cluster
      error_message = "Zero-egress mode requires private_cluster = true."
    }

    # RHCS owns version upgrades and mutable settings; do not hide drift.
    ignore_changes = [
      # Creation-only field: preserve existing clusters during bootstrap migration.
      admin_credentials,
    ]
  }
}

#------------------------------------------------------------------------------
# Wait for cluster endpoints and native admin bootstrap to settle
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
# RHCS 1.7.7 documents this HCP endpoint as unavailable. Input validation
# rejects enabling this resource until the provider/API supports it.
# Machine-pool autoscaling (min/max replicas) works without this resource.
#------------------------------------------------------------------------------
