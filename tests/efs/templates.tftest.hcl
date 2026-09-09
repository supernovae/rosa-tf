run "retained_tls_access_points" {
  command = plan
  assert {
    condition     = output.manifests.storageclass.reclaimPolicy == "Retain" && output.manifests.storageclass.mountOptions == ["tls"]
    error_message = "EFS must retain data and require encrypted mounts."
  }
  assert {
    condition     = output.manifests.storageclass.parameters.ensureUniqueDirectory == "true" && output.manifests.storageclass.parameters.reuseAccessPoint == "false" && output.manifests.storageclass.parameters.directoryPerms == "700"
    error_message = "Do not share directories or relax permissions across claims."
  }
  assert {
    condition     = !can(output.manifests.storageclass.metadata.annotations["storageclass.kubernetes.io/is-default-class"])
    error_message = "EFS must not become the cluster default."
  }
  assert {
    condition     = output.manifests.subscription.spec.installPlanApproval == "Manual" && output.manifests.subscription.spec.config.env[0].name == "ROLEARN"
    error_message = "Require controlled OLM approval and operator-managed STS credentials."
  }
}
run "govcloud_private_catalog" {
  command = plan
  variables {
    role_arn   = "arn:aws-us-gov:iam::123456789012:role/efs-csi"
    efs_config = { catalog_source = "approved-redhat", catalog_namespace = "private-catalog", manage_operator_group = false }
  }
  assert {
    condition     = output.manifests.subscription.spec.source == "approved-redhat" && startswith(output.manifests.subscription.spec.config.env[0].value, "arn:aws-us-gov:")
    error_message = "Preserve GovCloud role and private catalog configuration."
  }
}
run "reject_bad_approval" {
  command = plan
  variables { efs_config = { install_plan_approval = "Always" } }
  expect_failures = [var.efs_config]
}
run "reject_cidr_as_identity" {
  command = plan
  variables { efs_config = { allowed_security_group_ids = ["0.0.0.0/0"] } }
  expect_failures = [var.efs_config]
}
