run "modern_safe_defaults" {
  command = plan
  assert {
    condition     = output.manifests.subscription.spec.channel == "stable" && output.manifests.subscription.spec.installPlanApproval == "Automatic"
    error_message = "Use Red Hat's compatible stable channel and recommended automatic approval."
  }
  assert {
    condition     = !output.manifests.hco.spec.enableCommonBootImageImport && !can(output.manifests.hco.spec.featureGates)
    error_message = "Modern HCO must not emit deprecated feature gates or import public boot sources by default."
  }
  assert {
    condition     = output.manifests.hco.spec.uninstallStrategy == "BlockUninstallIfWorkloadsExist" && !can(output.manifests.hco.spec.resourceRequirements) && !can(output.manifests.hco.spec.liveMigrationConfig)
    error_message = "Block workload removal and defer CPU/migration tuning to supported operator defaults."
  }
  assert {
    condition     = length(output.manifests.hco.spec.infra.nodePlacement.nodeSelector) == 0 && length(output.manifests.hco.spec.workloads.nodePlacement.nodeSelector) == 1
    error_message = "Infra placement must be independent of VM placement."
  }
}
run "modern_schema_boundary" {
  command = plan
  variables { ocp_minor = 19 }
  assert {
    condition     = !output.manifests.hco.spec.enableCommonBootImageImport && !can(output.manifests.hco.spec.featureGates)
    error_message = "Use the top-level boot-source field from OpenShift 4.19 onward."
  }
}
run "netapp_profiles" {
  command = plan
  assert {
    condition     = output.manifests.san.spec.claimPropertySets[0].accessModes[0] == "ReadWriteMany" && output.manifests.san.spec.claimPropertySets[0].volumeMode == "Block" && output.manifests.nfs.spec.claimPropertySets[0].volumeMode == "Filesystem"
    error_message = "NetApp VM SAN must be RWX raw block; NFS must use filesystem mode."
  }
  assert {
    condition     = output.manifests.san.spec.cloneStrategy == "csi-clone" && output.manifests.san.spec.snapshotClass == "fsx-ontap-snapshots-retain"
    error_message = "Use explicit CSI clone and retained snapshot policies."
  }
}
run "older_schema_compatibility" {
  command = plan
  variables { ocp_minor = 18 }
  assert {
    condition     = !output.manifests.hco.spec.featureGates.enableCommonBootImageImport && !can(output.manifests.hco.spec.enableCommonBootImageImport)
    error_message = "Older HCO needs the legacy boot-source API, not an unknown field."
  }
}
run "manual_mirrored_catalog" {
  command = plan
  variables {
    virt_config = {
      install_plan_approval = "Manual"
      catalog_source        = "approved-mirror"
      catalog_namespace     = "catalogs"
      common_boot_images    = true
      infra_node_selector   = { "node-role.kubernetes.io/infra" = "" }
    }
  }
  assert {
    condition     = output.manifests.subscription.spec.source == "approved-mirror" && output.manifests.subscription.spec.sourceNamespace == "catalogs" && output.manifests.subscription.spec.installPlanApproval == "Manual" && output.manifests.hco.spec.enableCommonBootImageImport
    error_message = "Explicit catalog, approval and boot-image settings must render."
  }
}
run "reject_invalid_approval" {
  command = plan
  variables { virt_config = { install_plan_approval = "Unsafe" } }
  expect_failures = [var.virt_config]
}
run "reject_invalid_toleration" {
  command = plan
  variables {
    virt_config = { infra_tolerations = [{ key = "infra", operator = "Exists", value = "invalid", effect = "NoSchedule" }] }
  }
  expect_failures = [var.virt_config]
}
