#------------------------------------------------------------------------------
# Layer: OpenShift Virtualization (KubeVirt)
#
# Installs the OpenShift Virtualization operator for running VM workloads.
#
# Dependencies:
#   - Bare metal machine pool (from gitops-layers/virtualization module)
#------------------------------------------------------------------------------

locals {
  # Virtualization templates
  virt_subscription = templatefile("${local.layers_path}/virtualization/subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.virtualization
  })
  virt_hyperconverged = templatefile("${local.layers_path}/virtualization/hyperconverged.yaml.tftpl", {
    node_selector = var.virt_node_selector
    tolerations   = var.virt_tolerations
  })
}

#------------------------------------------------------------------------------
# Namespace
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "virtualization" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  metadata {
    name = "openshift-cnv"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "virtualization"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.wait_for_argocd_ready]
}

#------------------------------------------------------------------------------
# OperatorGroup
#------------------------------------------------------------------------------

resource "kubectl_manifest" "virt_operatorgroup" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  yaml_body = file("${local.layers_path}/virtualization/operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_namespace_v1.virtualization]
}

#------------------------------------------------------------------------------
# Subscription
#------------------------------------------------------------------------------

resource "kubectl_manifest" "virt_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  yaml_body = local.virt_subscription

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.virt_operatorgroup]
}

#------------------------------------------------------------------------------
# Wait for Virtualization operator
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_virt_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.virt_subscription]
}

#------------------------------------------------------------------------------
# HyperConverged CR
#------------------------------------------------------------------------------

resource "kubectl_manifest" "virt_hyperconverged" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  yaml_body = local.virt_hyperconverged

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_virt_operator]
}
