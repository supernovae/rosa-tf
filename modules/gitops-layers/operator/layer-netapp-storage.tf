#------------------------------------------------------------------------------
# Layer: NetApp Storage (FSx ONTAP + Astra Trident)
#
# Installs the Astra Trident Operator via OLM and configures:
#   - TridentOrchestrator CR (CSI driver deployment)
#   - NAS backend (ontap-nas) for NFS/RWX workloads
#   - SAN backend (ontap-san) for iSCSI/block workloads
#   - StorageClass: fsx-ontap-nfs-rwx   (Dev Spaces, shared volumes)
#   - StorageClass: fsx-ontap-iscsi-block (Virtualization, databases)
#   - VolumeSnapshotClass: fsx-ontap-snapshots (enterprise backups)
#
# Dependencies:
#   - FSx ONTAP filesystem + SVM (from gitops-layers/netapp-storage module)
#   - IAM role for Trident CSI (IRSA, from netapp-storage module)
#------------------------------------------------------------------------------

locals {
  # NetApp storage templates
  netapp_subscription = templatefile("${local.layers_path}/netapp-storage/subscription.yaml.tftpl", {
    operator_channel = "stable"
  })
  netapp_orchestrator = templatefile("${local.layers_path}/netapp-storage/trident-orchestrator.yaml.tftpl", {
    enable_fips   = var.netapp_enable_fips
    log_level     = var.netapp_trident_log_level
    trident_image = var.netapp_trident_image
  })
  netapp_backend_nas = templatefile("${local.layers_path}/netapp-storage/backend-config-nas.yaml.tftpl", {
    svm_management_ip = var.fsx_svm_management_ip
    svm_name          = var.fsx_svm_name
    backend_secret    = "backend-fsx-ontap-secret"
  })
  netapp_backend_san = templatefile("${local.layers_path}/netapp-storage/backend-config-san.yaml.tftpl", {
    svm_management_ip = var.fsx_svm_management_ip
    svm_name          = var.fsx_svm_name
    backend_secret    = "backend-fsx-ontap-secret"
  })
  netapp_sc_nfs   = file("${local.layers_path}/netapp-storage/storageclass-nfs-rwx.yaml.tftpl")
  netapp_sc_iscsi = file("${local.layers_path}/netapp-storage/storageclass-iscsi-block.yaml.tftpl")
  netapp_vs_class = file("${local.layers_path}/netapp-storage/volumesnapshotclass.yaml.tftpl")
}

#------------------------------------------------------------------------------
# Namespace
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "trident" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  metadata {
    name = "trident"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "netapp-storage"
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

resource "kubectl_manifest" "trident_operatorgroup" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = file("${local.layers_path}/netapp-storage/operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_namespace_v1.trident]
}

#------------------------------------------------------------------------------
# Subscription (OLM)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "trident_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_subscription

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.trident_operatorgroup]
}

#------------------------------------------------------------------------------
# Wait for Trident Operator
#
# The operator needs time to install and register CRDs
# (TridentOrchestrator, TridentBackendConfig, etc.)
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_trident_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  create_duration  = "120s"
  destroy_duration = "30s"

  depends_on = [kubectl_manifest.trident_subscription]
}

#------------------------------------------------------------------------------
# TridentOrchestrator CR
#
# Deploys the Trident CSI controller and node DaemonSet.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "trident_orchestrator" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_orchestrator

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_trident_operator]
}

#------------------------------------------------------------------------------
# Wait for Trident CSI driver to become ready
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_trident_csi" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  create_duration = "60s"

  depends_on = [kubectl_manifest.trident_orchestrator]
}

#------------------------------------------------------------------------------
# Backend Credentials Secret
#
# Stores the SVM vsadmin password for Trident backend authentication.
# The value comes from var.fsx_admin_password (sensitive, stored only in
# encrypted Terraform state). For production, consider External Secrets
# Operator to source from AWS Secrets Manager.
#------------------------------------------------------------------------------

resource "kubernetes_secret_v1" "trident_backend_credentials" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  metadata {
    name      = "backend-fsx-ontap-secret"
    namespace = "trident"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "netapp-storage"
    }
  }

  data = {
    username = base64encode("vsadmin")
    password = base64encode(var.fsx_admin_password)
  }

  depends_on = [time_sleep.wait_for_trident_csi]
}

#------------------------------------------------------------------------------
# Backend Configuration: NAS (NFS/RWX)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "trident_backend_nas" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_backend_nas

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_secret_v1.trident_backend_credentials]
}

#------------------------------------------------------------------------------
# Backend Configuration: SAN (iSCSI/Block)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "trident_backend_san" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_backend_san

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_secret_v1.trident_backend_credentials]
}

#------------------------------------------------------------------------------
# StorageClass: NFS RWX (Dev Spaces, shared volumes)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "sc_fsx_ontap_nfs_rwx" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_sc_nfs

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.trident_backend_nas]
}

#------------------------------------------------------------------------------
# StorageClass: iSCSI Block (Virtualization, databases)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "sc_fsx_ontap_iscsi_block" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_sc_iscsi

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.trident_backend_san]
}

#------------------------------------------------------------------------------
# VolumeSnapshotClass (enterprise backups)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "vs_fsx_ontap_snapshots" {
  count = !var.skip_k8s_destroy && var.enable_layer_netapp_storage ? 1 : 0

  yaml_body = local.netapp_vs_class

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    kubectl_manifest.trident_backend_nas,
    kubectl_manifest.trident_backend_san,
  ]
}
