run "secure_release_defaults" {
  command = plan
  assert {
    condition     = local.manifests.subscription.spec.startingCSV == "trident-operator.v26.6.1" && local.manifests.subscription.spec.installPlanApproval == "Manual"
    error_message = "Use the reviewed certified release and an approval gate for storage upgrades."
  }
  assert {
    condition     = !contains(keys(local.manifests.orchestrator.metadata), "namespace") && !local.manifests.orchestrator.spec.enableForceDetach && !local.manifests.orchestrator.spec.disableAuditLog
    error_message = "TridentOrchestrator is cluster scoped; force detach must be opt-in and audit logs retained."
  }
  assert {
    condition     = local.manifests.nas.spec.useREST && local.manifests.san.spec.useREST && local.manifests.nas.spec.autoExportCIDRs == ["10.1.0.0/24"] && !contains(keys(local.manifests.san.spec), "dataLIF")
    error_message = "Use REST, bounded export filters and SAN multipath discovery."
  }
  assert {
    condition     = local.manifests.nas.spec.deletionPolicy == "retain" && local.manifests.san.spec.deletionPolicy == "retain" && local.manifests.snapshot_class.deletionPolicy == "Retain"
    error_message = "Backend and snapshot removal must not silently destroy storage."
  }
}
run "container_and_vm_classes" {
  command = plan
  assert {
    condition     = local.manifests.san_class.parameters.fsType == "ext4" && !contains(keys(local.manifests.vm_class.parameters), "fsType")
    error_message = "VM RWX raw block must not inherit a filesystem format."
  }
  assert {
    condition     = alltrue([for m in [local.manifests.nfs_class, local.manifests.san_class, local.manifests.vm_class] : m.reclaimPolicy == "Retain" && m.allowVolumeExpansion && m.parameters.selector == "rosaLayer=netapp-storage"])
    error_message = "Retain important data, permit expansion and constrain backend selection."
  }
  assert {
    condition     = contains(local.manifests.nfs_class.mountOptions, "hard") && contains(local.manifests.nfs_class.mountOptions, "nfsvers=4.1")
    error_message = "Use hard NFSv4.1 mounts, never soft mounts for durable data."
  }
}
run "explicit_performance_and_private_registry" {
  command = plan
  variables {
    netapp_operator_config = { enable_concurrency = true, node_prep_iscsi = true, image_registry = "mirror.example.test/storage", image_pull_secrets = ["mirror-pull"] }
    netapp_storage_config  = { nfs_nconnect = 8, trusted_ca_pem = "-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----", qos_policy = "per-volume-gold" }
  }
  assert {
    condition     = local.manifests.orchestrator.spec.enableConcurrency && local.manifests.orchestrator.spec.nodePrep == ["iscsi"] && local.manifests.orchestrator.spec.imageRegistry == "mirror.example.test/storage"
    error_message = "Expose supported tuning and node preparation through the operator CR."
  }
  assert {
    condition     = contains(local.manifests.nfs_class.mountOptions, "nconnect=8") && base64decode(local.manifests.nas.spec.trustedCACertificate) == var.netapp_storage_config.trusted_ca_pem && local.manifests.san.spec.defaults.qosPolicy == "per-volume-gold"
    error_message = "Encode trusted CA once and carry explicit performance choices."
  }
}
run "reject_unsafe_mount_tuning" {
  command = plan
  variables { netapp_storage_config = { nfs_nconnect = 32 } }
  expect_failures = [var.netapp_storage_config]
}
