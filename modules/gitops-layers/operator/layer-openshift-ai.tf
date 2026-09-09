#------------------------------------------------------------------------------
# Layer: OpenShift AI (RHOAI)
#
# Installs the OpenShift AI 3.5 stack:
#   1. Node Feature Discovery (NFD) -- auto-discovers GPU hardware
#   2. NVIDIA GPU Operator -- drivers, device plugin, container toolkit
#   3. Red Hat OpenShift AI -- DataScienceCluster with configurable components
#
# RHOAI 3.5 uses KServe RawDeployment mode. Serverless is no longer required.
# cert-manager is required by KServe and Kueue. Service Mesh 3 is required only
# when the optional OGX component is enabled.
#
# Sub-toggles:
#   - openshift_ai_install_nfd: disable if NFD already installed
#   - openshift_ai_install_gpu_operator: disable for CPU-only AI workloads
#   - openshift_ai_create_s3: opt-in, only for AI Pipelines artifact storage
#
# Dependencies:
#   - GPU machine pool (configured in cluster phase via machine_pools variable)
#   - S3 bucket + IAM role (from openshift-ai resources module, only if create_s3=true)
#------------------------------------------------------------------------------

locals {
  # Gate expressions
  ai_enabled    = var.enable_layer_openshift_ai
  nfd_enabled   = local.ai_enabled && var.openshift_ai_install_nfd
  gpu_enabled   = local.ai_enabled && var.openshift_ai_install_gpu_operator
  kueue_enabled = local.ai_enabled && var.openshift_ai_install_kueue

  # NFD templates
  nfd_subscription = templatefile("${local.layers_path}/openshift-ai/nfd-subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.nfd
  })

  # GPU templates
  gpu_subscription = templatefile("${local.layers_path}/openshift-ai/gpu-subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.nvidia_gpu
  })
  gpu_clusterpolicy = file("${local.layers_path}/openshift-ai/gpu-clusterpolicy.yaml.tftpl")

  # Kueue templates
  kueue_subscription = templatefile("${local.layers_path}/openshift-ai/kueue-subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.kueue
  })

  # RHOAI templates
  rhoai_subscription = templatefile("${local.layers_path}/openshift-ai/rhoai-subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.openshift_ai
  })

  # Component defaults (RHOAI 3.5, DSC API v2).
  # kueue = "Unmanaged" integrates with the external Red Hat build of Kueue Operator.
  ai_default_components = {
    aigateway                  = "Removed"
    models_as_a_service        = "Removed"
    batch_gateway              = "Removed"
    dashboard                  = "Managed"
    workbenches                = "Managed"
    aipipelines                = "Managed"
    argo_workflows_controllers = "Managed"
    kserve                     = "Managed"
    nim                        = "Managed"
    wva                        = "Removed"
    kueue                      = "Unmanaged"
    trainingoperator           = "Removed"
    trainer                    = "Removed"
    ray                        = "Managed"
    trustyai                   = "Removed"
    modelregistry              = "Managed"
    feastoperator              = "Removed"
    llamastackoperator         = "Removed"
    ogx                        = "Removed"
    mlflowoperator             = "Removed"
    sparkoperator              = "Removed"
    mcplifecycleoperator       = "Removed"
  }
  ai_components = merge(local.ai_default_components, var.openshift_ai_components)

  rhoai_datasciencecluster = templatefile("${local.layers_path}/openshift-ai/rhoai-datasciencecluster.yaml.tftpl", merge(local.ai_components, {
    kserve_raw_deployment_service_config = var.openshift_ai_kserve_raw_deployment_service_config
    kueue_auto_create_queues             = var.openshift_ai_kueue_auto_create_queues
    kueue_default_cluster_queue_name     = var.openshift_ai_kueue_default_cluster_queue_name
    kueue_default_local_queue_name       = var.openshift_ai_kueue_default_local_queue_name
  }))
}

# RHOAI 3.5 supports OpenShift 4.19.9 and later. Keep the layer disabled on
# older GovCloud clusters until their control plane has been upgraded.
resource "terraform_data" "validate_openshift_ai_version" {
  count = local.ai_enabled ? 1 : 0

  lifecycle {
    precondition {
      condition = (
        local.ocp_major_version == 4 && (
          local.ocp_minor_version > 19 ||
          (local.ocp_minor_version == 19 && local.ocp_patch_version >= 9)
        )
      )
      error_message = "Red Hat OpenShift AI 3.5 requires OpenShift 4.19.9 or later; configured version is ${var.openshift_version}."
    }
  }
}

#==============================================================================
# STAGE 1: Node Feature Discovery (NFD)
#==============================================================================

resource "kubernetes_namespace_v1" "openshift_nfd" {
  count = local.nfd_enabled ? 1 : 0

  metadata {
    name = "openshift-nfd"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "openshift-ai"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.wait_for_argocd_ready, terraform_data.validate_openshift_ai_version]
}

resource "kubectl_manifest" "nfd_operatorgroup" {
  count = local.nfd_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/nfd-operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubernetes_namespace_v1.openshift_nfd]
}

resource "kubectl_manifest" "nfd_subscription" {
  count = local.nfd_enabled ? 1 : 0

  yaml_body = local.nfd_subscription

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.nfd_operatorgroup]
}

resource "time_sleep" "wait_for_nfd_operator" {
  count = local.nfd_enabled ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.nfd_subscription]
}

resource "kubectl_manifest" "nfd_nodefeaturediscovery" {
  count = local.nfd_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/nfd-nodefeaturediscovery.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_nfd_operator]
}

#==============================================================================
# STAGE 2: NVIDIA GPU Operator
#==============================================================================

resource "kubectl_manifest" "gpu_namespace" {
  count = local.gpu_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/gpu-namespace.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.nfd_nodefeaturediscovery]
}

resource "kubectl_manifest" "gpu_operatorgroup" {
  count = local.gpu_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/gpu-operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.gpu_namespace]
}

resource "kubectl_manifest" "gpu_subscription" {
  count = local.gpu_enabled ? 1 : 0

  yaml_body = local.gpu_subscription

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.gpu_operatorgroup]
}

resource "time_sleep" "wait_for_gpu_operator" {
  count = local.gpu_enabled ? 1 : 0

  create_duration = "120s"

  depends_on = [kubectl_manifest.gpu_subscription]
}

resource "kubectl_manifest" "gpu_clusterpolicy" {
  count = local.gpu_enabled ? 1 : 0

  yaml_body = local.gpu_clusterpolicy

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_gpu_operator]
}

#==============================================================================
# STAGE 3: Red Hat build of Kueue Operator
#
# External Kueue operator required for RHOAI 3.5 workload management.
# The DSC kueue component is set to "Unmanaged" to integrate with this.
#==============================================================================

resource "kubectl_manifest" "kueue_namespace" {
  count = local.kueue_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/kueue-namespace.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [
    kubectl_manifest.gpu_clusterpolicy,
    kubectl_manifest.nfd_nodefeaturediscovery,
    time_sleep.wait_for_argocd_ready,
    terraform_data.validate_openshift_ai_version
  ]
}

resource "kubectl_manifest" "kueue_operatorgroup" {
  count = local.kueue_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/kueue-operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.kueue_namespace]
}

resource "kubectl_manifest" "kueue_subscription" {
  count = local.kueue_enabled ? 1 : 0

  yaml_body = local.kueue_subscription

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.kueue_operatorgroup]
}

resource "time_sleep" "wait_for_kueue_operator" {
  count = local.kueue_enabled ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.kueue_subscription]
}

resource "kubectl_manifest" "kueue_cr" {
  count = local.kueue_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/kueue-cr.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_kueue_operator]
}

#==============================================================================
# STAGE 4: Red Hat OpenShift AI (RHOAI)
#
# RHOAI 3.5 uses KServe RawDeployment mode, which does not require Serverless.
# Service Mesh 3 remains an external prerequisite for the optional OGX component.
#==============================================================================

resource "kubectl_manifest" "rhoai_namespace" {
  count = local.ai_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/rhoai-namespace.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [
    kubectl_manifest.gpu_clusterpolicy,
    kubectl_manifest.kueue_cr,
    kubectl_manifest.nfd_nodefeaturediscovery,
    time_sleep.wait_for_argocd_ready,
    terraform_data.validate_openshift_ai_version
  ]
}

resource "kubectl_manifest" "rhoai_operatorgroup" {
  count = local.ai_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/rhoai-operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.rhoai_namespace]
}

resource "kubectl_manifest" "rhoai_subscription" {
  count = local.ai_enabled ? 1 : 0

  yaml_body = local.rhoai_subscription

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.rhoai_operatorgroup]
}

resource "time_sleep" "wait_for_rhoai_operator" {
  count = local.ai_enabled ? 1 : 0

  create_duration = "120s"

  depends_on = [kubectl_manifest.rhoai_subscription]
}

resource "kubectl_manifest" "rhoai_dscinitialize" {
  count = local.ai_enabled ? 1 : 0

  yaml_body = file("${local.layers_path}/openshift-ai/rhoai-dscinitialize.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_rhoai_operator]
}

resource "time_sleep" "wait_for_dsci_ready" {
  count = local.ai_enabled ? 1 : 0

  create_duration = "30s"

  depends_on = [kubectl_manifest.rhoai_dscinitialize]
}

resource "kubectl_manifest" "rhoai_datasciencecluster" {
  count = local.ai_enabled ? 1 : 0

  yaml_body = local.rhoai_datasciencecluster

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_dsci_ready]
}

#==============================================================================
# IRSA Annotations on RHOAI Service Accounts
#
# RHOAI workloads (KServe, pipelines, model serving) need S3 access.
# Annotating SAs with the IAM role ARN enables IRSA so pods get
# projected tokens and can assume the role without static credentials.
#==============================================================================

locals {
  rhoai_irsa_service_accounts = [
    "default",
    "ds-pipeline-dspa",
  ]
}

resource "kubectl_manifest" "rhoai_irsa_sa_annotation" {
  for_each = local.ai_enabled && var.openshift_ai_create_irsa ? toset(local.rhoai_irsa_service_accounts) : toset([])

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = each.value
      namespace = "redhat-ods-applications"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.openshift_ai_role_arn
      }
    }
  })

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.rhoai_datasciencecluster]
}

#==============================================================================
# S3 Data Connection Secret (optional)
#==============================================================================

resource "kubernetes_secret_v1" "rhoai_s3_data_connection" {
  count = local.ai_enabled && var.openshift_ai_create_s3 ? 1 : 0

  metadata {
    name      = "aws-connection-default"
    namespace = "redhat-ods-applications"

    labels = {
      "app.kubernetes.io/managed-by"   = "terraform"
      "app.kubernetes.io/part-of"      = "rosa-gitops-layers"
      "app.kubernetes.io/component"    = "openshift-ai"
      "opendatahub.io/dashboard"       = "true"
      "opendatahub.io/managed"         = "true"
      "opendatahub.io/secret-type"     = "aws"
      "opendatahub.io/connection-type" = "s3"
    }

    annotations = {
      "opendatahub.io/connection-type" = "s3"
      "openshift.io/display-name"      = "Terraform-managed S3"
    }
  }

  data = {
    AWS_ACCESS_KEY_ID     = ""
    AWS_SECRET_ACCESS_KEY = ""
    AWS_S3_ENDPOINT       = "https://${var.openshift_ai_s3_endpoint}"
    AWS_S3_BUCKET         = var.openshift_ai_bucket_name
    AWS_DEFAULT_REGION    = var.openshift_ai_bucket_region
  }

  depends_on = [kubectl_manifest.rhoai_datasciencecluster]
}
