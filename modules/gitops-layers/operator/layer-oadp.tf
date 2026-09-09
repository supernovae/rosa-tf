# OADP owns Velero, node agents and STS credentials. Terraform owns platform
# configuration; workload Backup/Restore objects belong to the recovery workflow.
locals {
  oadp_release = yamldecode(file("${local.layers_path}/oadp/release.yaml"))
  oadp_stream = try(one([for stream, release in local.oadp_release.streams :
    stream if contains(release.openshift_minors, local.ocp_minor_version)
  ]), "")
  oadp_virtualization_enabled = var.enable_layer_virtualization || var.oadp_config.virtualization_enabled
  oadp_node_agent_tolerations = distinct(concat(
    var.oadp_config.node_agent_tolerations,
    var.enable_layer_virtualization ? var.virt_tolerations : []
  ))
  oadp_subscription = templatefile("${local.layers_path}/oadp/subscription.yaml.tftpl", {
    config = var.oadp_config, role_arn = var.oadp_role_arn
  })
  oadp_dpa = templatefile("${local.layers_path}/oadp/dataprotectionapplication.yaml.tftpl", {
    bucket_name            = var.oadp_bucket_name, region = var.aws_region
    config                 = var.oadp_config, virtualization_enabled = local.oadp_virtualization_enabled
    node_agent_tolerations = local.oadp_node_agent_tolerations
  })
  oadp_schedule = templatefile("${local.layers_path}/oadp/schedule-nightly.yaml.tftpl", {
    cluster_name = var.cluster_name, backup_retention_days = var.oadp_backup_retention_days
    config       = var.oadp_config
  })
}

resource "kubernetes_namespace_v1" "oadp" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0
  metadata {
    name = "openshift-adp"
    labels = {
      "openshift.io/cluster-monitoring" = "true"
      "app.kubernetes.io/managed-by"    = "terraform"
      "app.kubernetes.io/part-of"       = "rosa-gitops-layers"
      "app.kubernetes.io/component"     = "oadp"
    }
  }
  lifecycle {
    ignore_changes  = [metadata[0].annotations]
    prevent_destroy = true
    precondition {
      condition     = local.ocp_major_version == 4 && contains([19, 20, 21, 22], local.ocp_minor_version)
      error_message = "Current OADP requires OpenShift 4.19–4.21 (1.5) or 4.22 (1.6). No current supported OADP path is documented for 4.18. Resolve the platform/support upgrade before enabling; do not install 1.6 on 4.21."
    }
    precondition {
      condition     = var.oadp_config.support_confirmed
      error_message = "Confirm OADP/ROSA region, platform, VM and CSI data-mover support before setting oadp_config.support_confirmed=true."
    }
    precondition {
      condition     = !local.oadp_virtualization_enabled || !var.oadp_config.filesystem_backup_enabled
      error_message = "VM protection uses CSI snapshots/data mover, not filesystem backup. Use a separate reviewed container-only policy for filesystem backups."
    }
    precondition {
      condition     = !var.oadp_config.schedule_enabled || var.oadp_backup_retention_days > 0
      error_message = "An enabled schedule needs a positive backup TTL."
    }
    precondition {
      condition     = var.oadp_bucket_name != "" && can(regex("^arn:aws(-us-gov)?:iam::[0-9]{12}:role/", var.oadp_role_arn))
      error_message = "Supply the provisioned OADP bucket and valid AWS partition-aware IAM role."
    }
  }
  depends_on = [time_sleep.wait_for_argocd_ready]
}
resource "kubectl_manifest" "oadp_operatorgroup" {
  count             = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0
  yaml_body         = file("${local.layers_path}/oadp/operatorgroup.yaml")
  server_side_apply = true
  force_conflicts   = false
  depends_on        = [kubernetes_namespace_v1.oadp]
}
resource "kubectl_manifest" "oadp_subscription" {
  count             = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0
  yaml_body         = local.oadp_subscription
  server_side_apply = true
  force_conflicts   = false
  wait_for {
    field {
      key        = "status.installedCSV"
      value      = "^oadp-operator[.]v${replace(coalesce(local.oadp_stream, "unsupported"), ".", "[.]")}[.]"
      value_type = "regex"
    }
  }
  timeouts {
    create = "45m"
    update = "45m"
  }
  depends_on = [kubectl_manifest.oadp_operatorgroup]
}
resource "time_sleep" "wait_for_oadp_operator" {
  count           = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0
  create_duration = "10s" # API-discovery propagation AFTER OLM installation.
  depends_on      = [kubectl_manifest.oadp_subscription]
}

# Transfer ownership to the OADP ROLEARN/STS flow without deleting the live Secret.
removed {
  from = kubectl_manifest.oadp_cloud_credentials
  lifecycle { destroy = false }
}

resource "kubectl_manifest" "oadp_netapp_snapshot_class" {
  count             = !var.skip_k8s_destroy && var.enable_layer_oadp && var.enable_layer_netapp_storage ? 1 : 0
  yaml_body         = file("${local.layers_path}/oadp/netapp-volumesnapshotclass.yaml")
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  depends_on        = [kubectl_manifest.trident_orchestrator]
}
resource "kubectl_manifest" "oadp_dpa" {
  count             = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0
  yaml_body         = local.oadp_dpa
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true
  wait_for {
    condition {
      type   = "Reconciled"
      status = "True"
    }
  }
  timeouts {
    create = "45m"
    update = "45m"
  }
  depends_on = [
    time_sleep.wait_for_oadp_operator,
    kubectl_manifest.oadp_netapp_snapshot_class,
    kubectl_manifest.virt_hyperconverged
  ]
}
resource "time_sleep" "wait_for_oadp_dpa" {
  count           = !var.skip_k8s_destroy && var.enable_layer_oadp && var.oadp_config.schedule_enabled ? 1 : 0
  create_duration = "10s"
  depends_on      = [kubectl_manifest.oadp_dpa]
}
resource "kubectl_manifest" "oadp_schedule" {
  count             = !var.skip_k8s_destroy && var.enable_layer_oadp && var.oadp_config.schedule_enabled && var.oadp_backup_retention_days > 0 ? 1 : 0
  yaml_body         = local.oadp_schedule
  server_side_apply = true
  force_conflicts   = false
  # Schedules are intentionally deletable; removing one stops new jobs.
  # useOwnerReferencesInBackup=false preserves existing Backup objects.
  depends_on = [time_sleep.wait_for_oadp_dpa]
}
