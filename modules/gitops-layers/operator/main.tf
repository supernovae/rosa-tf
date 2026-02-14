#------------------------------------------------------------------------------
# GitOps Module for ROSA
#
# This module installs the OpenShift GitOps operator (ArgoCD) and configures
# cluster resources using native Terraform providers. It provides:
#
# 1. Terraform Operator Identity (ServiceAccount + RBAC + token)
# 2. OpenShift GitOps Operator (ArgoCD) installation
# 3. ConfigMap bridge for Terraform-to-GitOps communication
# 4. Direct layer installation via kubectl_manifest resources
# 5. External repo Application (optional)
#
# IMPLEMENTATION NOTE:
# This module uses native hashicorp/kubernetes and alekc/kubectl providers
# instead of curl-based API calls. All K8s resources are in Terraform state,
# providing full lifecycle management (create, update, destroy).
#
# AUTHENTICATION:
# - Bootstrap (first run): OAuth token from cluster_auth module
# - Steady state: ServiceAccount token stored in Terraform state
# - See identity.tf for SA creation and token rotation documentation
#
# DESTRUCTION SAFETY:
# - Set skip_k8s_destroy = true before destroying the cluster
# - This prevents Terraform from trying to reach a dead API
# - See docs/OPERATIONS.md for the destroy workflow
#------------------------------------------------------------------------------

locals {
  api_url = trimsuffix(var.cluster_api_url, "/")

  #----------------------------------------------------------------------------
  # Path to layer manifests (shared by all layer-*.tf files)
  #----------------------------------------------------------------------------
  layers_path = "${path.module}/../../../gitops-layers/layers"

  #----------------------------------------------------------------------------
  # OpenShift Version Parsing
  # Used for operator channel selection and API compatibility
  #----------------------------------------------------------------------------
  ocp_version_parts = split(".", var.openshift_version)
  ocp_minor_version = length(local.ocp_version_parts) > 1 ? tonumber(local.ocp_version_parts[1]) : 20

  #----------------------------------------------------------------------------
  # Operator Channel Map
  #
  # Centralized operator channel selection based on OpenShift version.
  # Operators with generic channels (stable/fast) auto-select versions via OLM.
  # Only operators with version-specific channels need explicit selection.
  #
  # To add a new version-specific operator:
  # 1. Add entry to this map with version logic
  # 2. Create .yaml.tftpl template with ${operator_channel} placeholder
  # 3. Reference in the appropriate layer-*.tf file
  #----------------------------------------------------------------------------
  operator_channels = {
    # Logging stack requires version-specific channels
    # stable-6.2: OCP 4.16, 4.17, 4.18 (GovCloud)
    # stable-6.4: OCP 4.19+ (Commercial)
    loki            = local.ocp_minor_version >= 19 ? "stable-6.4" : "stable-6.2"
    cluster_logging = local.ocp_minor_version >= 19 ? "stable-6.4" : "stable-6.2"

    # These operators use generic channels that auto-select appropriate versions
    # Listed here for documentation and future version-specific needs
    oadp           = "stable" # Auto-selects based on OCP version
    virtualization = "stable" # Auto-selects based on OCP version
    web_terminal   = "fast"   # Uses latest available
    gitops         = "latest" # OpenShift GitOps operator
  }

  # Whether the user has provided a custom GitOps repo for additional resources.
  # When true, a single ArgoCD Application is created to sync from that repo.
  has_custom_gitops_repo = var.gitops_repo_url != "https://github.com/redhat-openshift-ecosystem/rosa-gitops-layers.git"

  # ConfigMap data -- passes Terraform-managed values to GitOps layers
  configmap_data = merge(
    {
      cluster_name                 = var.cluster_name
      aws_region                   = var.aws_region
      aws_account                  = var.aws_account_id
      gitops_repo_url              = var.gitops_repo_url
      gitops_repo_revision         = var.gitops_repo_revision
      gitops_repo_path             = var.gitops_repo_path
      layer_terminal_enabled       = tostring(var.enable_layer_terminal)
      layer_oadp_enabled           = tostring(var.enable_layer_oadp)
      layer_virtualization_enabled = tostring(var.enable_layer_virtualization)
      layer_monitoring_enabled     = tostring(var.enable_layer_monitoring)
      layer_certmanager_enabled    = tostring(var.enable_layer_certmanager)
    },
    var.enable_layer_oadp ? {
      oadp_bucket_name = var.oadp_bucket_name
      oadp_role_arn    = var.oadp_role_arn
      oadp_region      = var.aws_region
    } : {},
    var.enable_layer_monitoring ? {
      monitoring_bucket_name    = var.monitoring_bucket_name
      monitoring_role_arn       = var.monitoring_role_arn
      monitoring_retention_days = tostring(var.monitoring_retention_days)
    } : {},
    var.enable_layer_certmanager ? {
      certmanager_role_arn           = var.certmanager_role_arn
      certmanager_hosted_zone_id     = var.certmanager_hosted_zone_id
      certmanager_hosted_zone_domain = var.certmanager_hosted_zone_domain
      certmanager_acme_email         = var.certmanager_acme_email
    } : {},
    var.additional_config_data
  )
}
