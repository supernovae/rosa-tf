#------------------------------------------------------------------------------
# GitOps Module for ROSA
#
# This module installs the OpenShift GitOps operator (ArgoCD) and configures
# cluster resources using native Terraform providers. It provides:
#
# 1. Terraform Operator Identity (ServiceAccount + RBAC + token)
# 2. OpenShift GitOps Operator (ArgoCD) installation
# 3. Direct layer installation via kubectl_manifest resources
# 4. External repo Application (optional)
#
# IMPLEMENTATION NOTE:
# This module uses native hashicorp/kubernetes and alekc/kubectl providers
# instead of curl-based API calls. All K8s resources are in Terraform state,
# providing full lifecycle management (create, update, destroy).
#
# AUTHENTICATION:
# Supply short-lived runner credentials; verified-TLS OAuth is a bootstrap fallback.
# Legacy permanent SA token creation requires explicit opt-in.
# Retained namespaces/default project are not deleted with module removal.
# skip_k8s_destroy is a count switch, NOT a state-forgetting mechanism.
# See docs/GITOPS.md for migration, lifecycle and ownership requirements.
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
  ocp_major_version = length(local.ocp_version_parts) > 0 ? tonumber(local.ocp_version_parts[0]) : 4
  ocp_minor_version = length(local.ocp_version_parts) > 1 ? tonumber(local.ocp_version_parts[1]) : 20
  ocp_patch_version = length(local.ocp_version_parts) > 2 ? tonumber(local.ocp_version_parts[2]) : 0

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
    # 2026-09: 6.6 requires 4.20+; 6.5 supports 4.19; 6.2 is the
    # remaining EUS stream for 4.16-4.18 (confirm entitlement with Red Hat).
    # 6.4 is compatible with 4.18 but has ENDED maintenance. Do not select it.
    loki            = local.monitoring_logging_channel
    cluster_logging = local.monitoring_logging_channel

    # These operators use generic channels that auto-select appropriate versions
    # Listed here for documentation and future version-specific needs
    oadp           = "stable"             # Auto-selects based on OCP version
    virtualization = "stable"             # Auto-selects based on OCP version
    web_terminal   = "fast"               # Uses latest available
    gitops         = local.gitops_channel # Supported, minor-pinned OpenShift GitOps stream

    # OpenShift AI 3.5 stack (KServe uses RawDeployment; no Serverless dependency)
    nfd          = "stable"      # Node Feature Discovery
    nvidia_gpu   = "v26.7"       # NVIDIA GPU Operator (certified-operators)
    openshift_ai = "stable-3.5"  # Red Hat OpenShift AI 3.5 GA (RHOAI)
    kueue        = "stable-v1.4" # Red Hat build of Kueue Operator
  }

  # Whether the user has provided a custom GitOps repo for additional resources.
  # When true, a single ArgoCD Application is created to sync from that repo.
  has_custom_gitops_repo = var.gitops_application.enabled

}
