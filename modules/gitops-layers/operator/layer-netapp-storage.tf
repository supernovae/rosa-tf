# NetApp Trident: supported operator owns CSI operands; Terraform owns infrastructure
# and storage policy. Read docs/NETAPP-STORAGE.md before an existing-install upgrade.
locals {
  netapp_release             = yamldecode(file("${local.layers_path}/netapp-storage/release.yaml"))
  netapp_backend_secret      = var.netapp_storage_config.backend_secret_name != "" ? var.netapp_storage_config.backend_secret_name : "backend-fsx-ontap-secret"
  netapp_management_endpoint = var.netapp_storage_config.management_endpoint != "" ? var.netapp_storage_config.management_endpoint : var.fsx_svm_management_ip
  netapp_subscription = templatefile("${local.layers_path}/netapp-storage/subscription.yaml.tftpl", {
    release = local.netapp_release, config = var.netapp_operator_config
  })
  netapp_orchestrator = templatefile("${local.layers_path}/netapp-storage/trident-orchestrator.yaml.tftpl", {
    config = var.netapp_operator_config, log_level = var.netapp_trident_log_level, trident_image = var.netapp_trident_image
  })
  netapp_backend_nas = templatefile("${local.layers_path}/netapp-storage/backend-config-nas.yaml.tftpl", {
    management_endpoint = local.netapp_management_endpoint, nfs_endpoint = var.fsx_svm_nfs_endpoint
    svm_name            = var.fsx_svm_name, backend_secret = local.netapp_backend_secret
    client_cidrs        = var.netapp_client_cidrs, config = var.netapp_storage_config
  })
  netapp_backend_san = templatefile("${local.layers_path}/netapp-storage/backend-config-san.yaml.tftpl", {
    management_endpoint = local.netapp_management_endpoint, svm_name = var.fsx_svm_name
    backend_secret      = local.netapp_backend_secret, config = var.netapp_storage_config
  })
  netapp_storage_classes = {
    for name, protocol in {
      fsx-ontap-nfs-retain = "nfs"
      fsx-ontap-san-retain = "san-filesystem"
      fsx-ontap-vm-rwx     = "san-block"
      } : name => templatefile("${local.layers_path}/netapp-storage/storageclass.yaml.tftpl", {
        name = name, protocol = protocol, nconnect = var.netapp_storage_config.nfs_nconnect
    }) if protocol == "nfs" || var.netapp_storage_config.san_enabled
  }
}

resource "kubernetes_namespace_v1" "trident" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  metadata {
    name   = "trident"
    labels = { "app.kubernetes.io/managed-by" = "terraform", "app.kubernetes.io/part-of" = "rosa-gitops-layers", "app.kubernetes.io/component" = "netapp-storage" }
  }
  lifecycle {
    ignore_changes  = [metadata[0].annotations]
    prevent_destroy = true # Contains CSI state and backend credentials.
  }
  depends_on = [time_sleep.wait_for_argocd_ready]
}
resource "kubectl_manifest" "trident_operatorgroup" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  yaml_body         = file("${local.layers_path}/netapp-storage/operatorgroup.yaml")
  server_side_apply = true
  force_conflicts   = false
  depends_on        = [kubernetes_namespace_v1.trident]
}
resource "kubectl_manifest" "trident_subscription" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  yaml_body         = local.netapp_subscription
  server_side_apply = true
  force_conflicts   = false
  lifecycle {
    precondition {
      condition     = contains(local.netapp_release.openshift_minors, "${local.ocp_major_version}.${local.ocp_minor_version}")
      error_message = "No verified certified Trident release for this OpenShift minor."
    }
    precondition {
      condition     = strcontains(var.netapp_storage_config.trusted_ca_pem, "-----BEGIN CERTIFICATE-----")
      error_message = "Supply trusted ONTAP CA PEM and a certificate-matching management endpoint. Empty CA would disable Trident TLS verification."
    }
    precondition {
      condition     = length(var.netapp_client_cidrs) > 0 && alltrue([for cidr in var.netapp_client_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 16, false)])
      error_message = "Provide approved IPv4 worker CIDRs (/16 or narrower) for automatic export filtering."
    }
    precondition {
      condition     = !var.netapp_storage_config.san_enabled || var.netapp_operator_config.node_prep_iscsi || var.netapp_operator_config.nodes_prepared
      error_message = "SAN requires explicit operator iSCSI node preparation (may roll workers), or verified pre-prepared nodes."
    }
    precondition {
      condition     = !var.netapp_storage_config.san_enabled || !var.netapp_storage_config.use_chap || var.netapp_storage_config.backend_secret_name != ""
      error_message = "CHAP requires an externally managed backend Secret with ONTAP authentication and all four CHAP keys. See docs/NETAPP-STORAGE.md."
    }
  }
  depends_on = [kubectl_manifest.trident_operatorgroup]
}
resource "time_sleep" "wait_for_trident_operator" {
  count            = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  create_duration  = "120s"
  destroy_duration = "30s"
  depends_on       = [kubectl_manifest.trident_subscription]
}
resource "kubectl_manifest" "trident_orchestrator" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  yaml_body         = local.netapp_orchestrator
  server_side_apply = true
  force_conflicts   = false
  wait_for {
    field {
      key   = "status.status"
      value = "Installed"
    }
  }
  timeouts {
    create = "30m"
    update = "30m"
  }
  depends_on = [time_sleep.wait_for_trident_operator]
}
resource "time_sleep" "wait_for_trident_csi" {
  count           = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  create_duration = "10s"
  depends_on      = [kubectl_manifest.trident_orchestrator]
}
# Compatibility fallback. Prefer externally managed SVM credentials, not fsxadmin.
# Kubernetes provider data expects plaintext strings and performs base64 encoding.
resource "kubernetes_secret_v1" "trident_backend_credentials" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage && var.netapp_storage_config.backend_secret_name == "" ? 1 : 0
  metadata {
    name      = "backend-fsx-ontap-secret"
    namespace = "trident"
  }
  data = { username = "vsadmin", password = var.fsx_admin_password }
  lifecycle {
    precondition {
      condition     = var.fsx_admin_password != ""
      error_message = "Provide SVM credentials or a separately managed backend Secret."
    }
  }
  depends_on = [time_sleep.wait_for_trident_csi]
}
resource "kubectl_manifest" "trident_backend_nas" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  yaml_body         = local.netapp_backend_nas
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }
  timeouts {
    create = "15m"
    update = "15m"
  }
  depends_on = [kubernetes_secret_v1.trident_backend_credentials, time_sleep.wait_for_trident_csi]
}
resource "kubectl_manifest" "trident_backend_san" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage && var.netapp_storage_config.san_enabled ? 1 : 0
  yaml_body         = local.netapp_backend_san
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }
  timeouts {
    create = "15m"
    update = "15m"
  }
  depends_on = [kubernetes_secret_v1.trident_backend_credentials, time_sleep.wait_for_trident_csi]
}
resource "kubectl_manifest" "netapp_storage_class" {
  for_each          = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? local.netapp_storage_classes : {}
  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [kubectl_manifest.trident_backend_nas, kubectl_manifest.trident_backend_san]
}
resource "kubectl_manifest" "netapp_snapshot_class_retain" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0
  yaml_body         = file("${local.layers_path}/netapp-storage/snapshotclass-retain.yaml")
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [kubectl_manifest.trident_backend_nas]
}
# Preserve immutable legacy classes only during an explicit existing-volume migration.
# They retain their original Delete policy; new claims should use the retained classes.
resource "kubectl_manifest" "sc_fsx_ontap_nfs_rwx" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage && var.netapp_storage_config.legacy_classes_enabled ? 1 : 0
  yaml_body         = file("${local.layers_path}/netapp-storage/storageclass-nfs-rwx.yaml.tftpl")
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [time_sleep.wait_for_trident_csi]
}
resource "kubectl_manifest" "sc_fsx_ontap_iscsi_block" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage && var.netapp_storage_config.legacy_classes_enabled ? 1 : 0
  yaml_body         = file("${local.layers_path}/netapp-storage/storageclass-iscsi-block.yaml.tftpl")
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [time_sleep.wait_for_trident_csi]
}
resource "kubectl_manifest" "vs_fsx_ontap_snapshots" {
  count             = !var.skip_k8s_destroy && var.enable_layer_netapp_storage && var.netapp_storage_config.legacy_classes_enabled ? 1 : 0
  yaml_body         = file("${local.layers_path}/netapp-storage/volumesnapshotclass.yaml.tftpl")
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [time_sleep.wait_for_trident_csi]
}
