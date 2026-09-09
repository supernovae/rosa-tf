#------------------------------------------------------------------------------
# Layer: OpenShift Virtualization (KubeVirt)
#
# Installs the OpenShift Virtualization operator for running VM workloads.
#
# Dependencies:
#   - Supported bare metal machine pools created through the environment root
#   - Explicit platform/region/storage support confirmation
#------------------------------------------------------------------------------

locals {
  # Virtualization templates
  virt_subscription = templatefile("${local.layers_path}/virtualization/subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.virtualization
    config           = var.virt_config
  })
  virt_hyperconverged = templatefile("${local.layers_path}/virtualization/hyperconverged.yaml.tftpl", {
    node_selector     = var.virt_node_selector
    tolerations       = var.virt_tolerations
    config            = var.virt_config
    modern_boot_field = local.ocp_minor_version >= 19
  })
  virt_netapp_profiles = var.virt_config.netapp_storage_profiles && var.enable_layer_netapp_storage ? merge(
    { fsx-ontap-nfs-retain = "Filesystem" },
    var.netapp_storage_config.san_enabled ? { fsx-ontap-vm-rwx = "Block" } : {}
  ) : {}
}

#------------------------------------------------------------------------------
# Namespace
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "virtualization" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  metadata {
    name = "openshift-cnv"

    labels = {
      "app.kubernetes.io/managed-by"    = "terraform"
      "app.kubernetes.io/part-of"       = "rosa-gitops-layers"
      "app.kubernetes.io/component"     = "virtualization"
      "openshift.io/cluster-monitoring" = "true"
    }
  }

  lifecycle {
    ignore_changes  = [metadata[0].annotations]
    prevent_destroy = true
    precondition {
      condition     = var.virt_config.platform_support_confirmed
      error_message = "Confirm Red Hat and NetApp support for the ROSA architecture, region, OpenShift version and bare-metal/storage configuration; then set virt_config.platform_support_confirmed=true. HCP/GovCloud support must not be inferred from shared Terraform wiring."
    }
    precondition {
      condition     = local.ocp_major_version == 4 && local.ocp_minor_version >= 18 && local.ocp_minor_version <= 22
      error_message = "Virtualization templates cover OpenShift 4.18–4.22; verify catalog availability, lifecycle entitlement and schemas before adding another minor."
    }
    precondition {
      condition     = length(var.virt_node_selector) > 0
      error_message = "Select a verified bare-metal VM worker pool explicitly."
    }
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
  force_conflicts   = false

  depends_on = [kubernetes_namespace_v1.virtualization]
}

#------------------------------------------------------------------------------
# Subscription
#------------------------------------------------------------------------------

resource "kubectl_manifest" "virt_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  yaml_body = local.virt_subscription

  server_side_apply = true
  force_conflicts   = false
  wait_for {
    field {
      key        = "status.installedCSV"
      value      = "^kubevirt-hyperconverged-operator[.]v${local.ocp_major_version}[.]${local.ocp_minor_version}[.]"
      value_type = "regex"
    }
  }
  timeouts {
    create = "45m"
    update = "45m"
  }

  depends_on = [kubectl_manifest.virt_operatorgroup]
}

#------------------------------------------------------------------------------
# Wait for Virtualization operator
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_virt_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  # Short API-discovery propagation delay AFTER OLM records an installed CSV.
  create_duration = "10s"

  depends_on = [kubectl_manifest.virt_subscription]
}

#------------------------------------------------------------------------------
# HyperConverged CR
#------------------------------------------------------------------------------

resource "kubectl_manifest" "virt_hyperconverged" {
  count = !var.skip_k8s_destroy && var.enable_layer_virtualization ? 1 : 0

  yaml_body = local.virt_hyperconverged

  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  wait_for {
    condition {
      type   = "Available"
      status = "True"
    }
    condition {
      type   = "Degraded"
      status = "False"
    }
    condition {
      type   = "Progressing"
      status = "False"
    }
  }
  timeouts {
    create = "45m"
    update = "45m"
  }

  depends_on = [time_sleep.wait_for_virt_operator]
}

# CDI owns generated status; Terraform manages only explicit storage policy.
# Profiles exist only when both layers are enabled; SAN is additionally opt-in.
resource "kubectl_manifest" "virt_netapp_storage_profile" {
  for_each = !var.skip_k8s_destroy && var.enable_layer_virtualization ? local.virt_netapp_profiles : {}
  yaml_body = templatefile("${local.layers_path}/virtualization/storageprofile.yaml.tftpl", {
    storage_class = each.key, volume_mode = each.value
  })
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on = [
    kubectl_manifest.virt_hyperconverged,
    kubectl_manifest.netapp_storage_class,
    kubectl_manifest.netapp_snapshot_class_retain
  ]
}
