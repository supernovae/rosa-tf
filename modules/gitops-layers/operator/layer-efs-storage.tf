# Red Hat's catalog delivers the cluster-compatible EFS operator and operands.
# Do not install an upstream Helm driver alongside it or override operand images.
locals {
  efs_release = yamldecode(file("${local.layers_path}/efs-storage/release.yaml"))
  efs_subscription = templatefile("${local.layers_path}/efs-storage/subscription.yaml.tftpl", {
    config = var.efs_config, role_arn = var.efs_role_arn
  })
  efs_cluster_csi_driver = file("${local.layers_path}/efs-storage/cluster-csi-driver.yaml.tftpl")
  efs_storageclass = templatefile("${local.layers_path}/efs-storage/storageclass.yaml.tftpl", {
    efs_file_system_id = var.efs_file_system_id, storage_class_name = var.efs_storage_class_name
  })
}
resource "kubectl_manifest" "efs_operatorgroup" {
  count             = var.enable_layer_efs_storage && var.efs_config.manage_operator_group ? 1 : 0
  yaml_body         = file("${local.layers_path}/efs-storage/operatorgroup.yaml")
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [time_sleep.wait_for_argocd_ready]
}
resource "kubectl_manifest" "efs_subscription" {
  count             = var.enable_layer_efs_storage ? 1 : 0
  yaml_body         = local.efs_subscription
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  wait_for {
    field {
      key        = "status.installedCSV"
      value      = "^aws-efs-csi-driver-operator[.]v${local.ocp_major_version}[.]${local.ocp_minor_version}[.]"
      value_type = "regex"
    }
  }
  timeouts {
    create = "45m"
    update = "45m"
  }
  lifecycle {
    precondition {
      condition     = can(regex("^arn:aws(-us-gov)?:iam::[0-9]{12}:role/", var.efs_role_arn)) && can(regex("^fs-[a-f0-9]+$", var.efs_file_system_id))
      error_message = "Supply the provisioned regional EFS filesystem and controller STS role."
    }
    precondition {
      condition     = local.ocp_major_version == 4 && contains(local.efs_release.openshift_minors, local.ocp_minor_version)
      error_message = "EFS contracts are reviewed for OpenShift 4.18–4.22. Review vendor support/catalog before adding another minor."
    }
  }
  depends_on = [kubectl_manifest.efs_operatorgroup, time_sleep.wait_for_argocd_ready]
}
resource "time_sleep" "wait_for_efs_operator" {
  count           = var.enable_layer_efs_storage ? 1 : 0
  create_duration = "10s" # discovery propagation after OLM has installed the CSV
  depends_on      = [kubectl_manifest.efs_subscription]
}
# ROLEARN/CCO owns the credentials. Preserve the existing live Secret on migration.
removed {
  from = kubernetes_secret_v1.efs_csi_credentials
  lifecycle { destroy = false }
}
resource "kubectl_manifest" "efs_cluster_csi_driver" {
  count             = var.enable_layer_efs_storage ? 1 : 0
  yaml_body         = local.efs_cluster_csi_driver
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
  }
  timeouts {
    create = "30m"
    update = "30m"
  }
  depends_on = [time_sleep.wait_for_efs_operator]
}
resource "time_sleep" "wait_for_efs_csi_driver" {
  count           = var.enable_layer_efs_storage ? 1 : 0
  create_duration = "10s"
  depends_on      = [kubectl_manifest.efs_cluster_csi_driver]
}
resource "kubectl_manifest" "efs_storageclass" {
  count             = var.enable_layer_efs_storage ? 1 : 0
  yaml_body         = local.efs_storageclass
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true # preserve previous classes/PV references when renamed
  depends_on        = [time_sleep.wait_for_efs_csi_driver]
}
