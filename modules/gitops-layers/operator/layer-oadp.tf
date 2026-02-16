#------------------------------------------------------------------------------
# Layer: OADP (OpenShift API for Data Protection)
#
# Installs the OADP operator (Velero) and configures backup/restore with
# Terraform-provisioned S3 storage and IRSA-based IAM authentication.
#
# Dependencies:
#   - S3 bucket from gitops-layers/oadp module
#   - IAM role with OIDC trust from gitops-layers/oadp module
#------------------------------------------------------------------------------

locals {
  # OADP templates
  oadp_credentials = templatefile("${local.layers_path}/oadp/velero-aws-config.yaml.tftpl", {
    role_arn = var.oadp_role_arn
  })
  oadp_dpa = templatefile("${local.layers_path}/oadp/dataprotectionapplication.yaml.tftpl", {
    bucket_name = var.oadp_bucket_name
    region      = var.aws_region
    role_arn    = var.oadp_role_arn
  })
  oadp_schedule = templatefile("${local.layers_path}/oadp/schedule-nightly.yaml.tftpl", {
    cluster_name          = var.cluster_name
    backup_retention_days = var.oadp_backup_retention_days
  })
}

#------------------------------------------------------------------------------
# Namespace
#------------------------------------------------------------------------------

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
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.wait_for_argocd_ready]
}

#------------------------------------------------------------------------------
# OperatorGroup
#------------------------------------------------------------------------------

resource "kubectl_manifest" "oadp_operatorgroup" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0

  yaml_body = file("${local.layers_path}/oadp/operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_namespace_v1.oadp]
}

#------------------------------------------------------------------------------
# Subscription
#------------------------------------------------------------------------------

resource "kubectl_manifest" "oadp_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0

  yaml_body = file("${local.layers_path}/oadp/subscription.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.oadp_operatorgroup]
}

#------------------------------------------------------------------------------
# Wait for OADP operator to install
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_oadp_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.oadp_subscription]
}

#------------------------------------------------------------------------------
# Cloud Credentials Secret (IRSA)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "oadp_cloud_credentials" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0

  yaml_body = local.oadp_credentials

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_namespace_v1.oadp]
}

#------------------------------------------------------------------------------
# DataProtectionApplication
#------------------------------------------------------------------------------

resource "kubectl_manifest" "oadp_dpa" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp ? 1 : 0

  yaml_body = local.oadp_dpa

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    time_sleep.wait_for_oadp_operator,
    kubectl_manifest.oadp_cloud_credentials,
  ]
}

#------------------------------------------------------------------------------
# Wait for DPA to reconcile before creating schedule
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_oadp_dpa" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp && var.oadp_backup_retention_days > 0 ? 1 : 0

  create_duration = "30s"

  depends_on = [kubectl_manifest.oadp_dpa]
}

#------------------------------------------------------------------------------
# Nightly Backup Schedule
#------------------------------------------------------------------------------

resource "kubectl_manifest" "oadp_schedule" {
  count = !var.skip_k8s_destroy && var.enable_layer_oadp && var.oadp_backup_retention_days > 0 ? 1 : 0

  yaml_body = local.oadp_schedule

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_oadp_dpa]
}
