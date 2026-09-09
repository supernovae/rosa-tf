run "secure_csi_defaults" {
  command = plan
  assert {
    condition     = output.stream == "1.6" && output.manifests.subscription.spec.channel == "stable" && output.manifests.subscription.spec.installPlanApproval == "Manual"
    error_message = "Use the supported OADP stream and reviewed upgrades."
  }
  assert {
    condition     = output.manifests.subscription.spec.config.env[0].name == "ROLEARN" && output.manifests.dpa.spec.backupLocations[0].velero.credential.key == "credentials"
    error_message = "OADP owns the STS credentials Secret through ROLEARN."
  }
  assert {
    condition     = output.manifests.dpa.spec.configuration.velero.disableFsBackup && output.manifests.dpa.spec.configuration.velero.defaultSnapshotMoveData && output.manifests.dpa.spec.configuration.nodeAgent.uploaderType == "kopia"
    error_message = "Default to CSI/Kopia data movement without privileged filesystem backup."
  }
  assert {
    condition     = !contains(output.manifests.dpa.spec.configuration.velero.defaultPlugins, "kubevirt") && !can(output.manifests.dpa.spec.snapshotLocations)
    error_message = "Do not enable VM plugins without VM intent or nonexistent native snapshot locations."
  }
}
run "vm_netapp_backup" {
  command = plan
  variables {
    virtualization_enabled = true
    oadp_config = {
      included_namespaces    = ["vm-workloads"]
      schedule_enabled       = true
      node_agent_tolerations = [{ key = "virtualization", value = "true", operator = "Equal", effect = "NoSchedule" }]
    }
  }
  assert {
    condition     = contains(output.manifests.dpa.spec.configuration.velero.defaultPlugins, "kubevirt") && output.manifests.dpa.spec.configuration.nodeAgent.podConfig.tolerations[0].effect == "NoSchedule"
    error_message = "VM backups require the KubeVirt plugin and placement on tainted workers."
  }
  assert {
    condition     = output.manifests.schedule.spec.paused && !output.manifests.schedule.spec.useOwnerReferencesInBackup && output.manifests.schedule.spec.template.includedNamespaces[0] == "vm-workloads" && output.manifests.schedule.spec.template.snapshotMoveData && !output.manifests.schedule.spec.template.defaultVolumesToFsBackup
    error_message = "Schedules must be scoped, initially paused, CSI-based and preserve existing backups."
  }
  assert {
    condition     = !can(output.manifests.schedule.spec.template.volumeSnapshotLocations) && !can(output.manifests.schedule.spec.template.includeClusterResources) && output.manifests.snapshot_class.deletionPolicy == "Delete" && output.manifests.snapshot_class.metadata.labels["velero.io/csi-volumesnapshot-class"] == "true"
    error_message = "Use CSI staging snapshots and related-resource auto mode, not native VSL references."
  }
}
run "commercial_compatible_stream" {
  command = plan
  variables { openshift_version = "4.20.14" }
  assert {
    condition     = output.stream == "1.5"
    error_message = "Do not select OADP 1.6 on OpenShift 4.20."
  }
}
run "govcloud_mirrored_catalog" {
  command = plan
  variables {
    region   = "us-gov-west-1"
    role_arn = "arn:aws-us-gov:iam::123456789012:role/backup-role"
    oadp_config = {
      catalog_source        = "approved-mirror"
      catalog_namespace     = "catalogs"
      install_plan_approval = "Automatic"
    }
  }
  assert {
    condition     = output.manifests.subscription.spec.config.env[0].value == "arn:aws-us-gov:iam::123456789012:role/backup-role" && output.manifests.dpa.spec.backupLocations[0].velero.config.region == "us-gov-west-1"
    error_message = "Preserve GovCloud region and partition."
  }
}
run "reject_wildcard" {
  command = plan
  variables { oadp_config = { included_namespaces = ["*"] } }
  expect_failures = [var.oadp_config]
}
run "reject_platform_namespace" {
  command = plan
  variables { oadp_config = { included_namespaces = ["openshift-cnv"] } }
  expect_failures = [var.oadp_config]
}
run "reject_empty_schedule_scope" {
  command = plan
  variables { oadp_config = { schedule_enabled = true } }
  expect_failures = [var.oadp_config]
}
run "reject_unsupported_418" {
  command = plan
  variables {
    enable_layer_oadp = true
    openshift_version = "4.18.44"
    oadp_config       = { support_confirmed = true }
  }
  expect_failures = [var.oadp_config]
}
run "reject_unconfirmed_support" {
  command = plan
  variables { enable_layer_oadp = true }
  expect_failures = [var.oadp_config]
}
