#------------------------------------------------------------------------------
# Layer: EFS Storage (AWS EFS CSI Driver)
#
# Installs the AWS EFS CSI Driver Operator via OLM and configures:
#   - ClusterCSIDriver CR (triggers the operator to deploy the EFS driver)
#   - Secret with IAM role ARN for IRSA authentication
#   - StorageClass: efs-sc (dynamic PV provisioning via EFS access points)
#
# Dependencies:
#   - EFS filesystem + mount targets + security group (from efs-storage resources module)
#   - IAM role for EFS CSI driver (IRSA, from efs-storage module)
#
# Classic / HCP / GovCloud Parity:
#   The EFS CSI Driver Operator is available in redhat-operators catalog on
#   all ROSA variants. IRSA handles the authentication; no node-level policies
#   needed on machine pools or Karpenter NodePools.
#------------------------------------------------------------------------------

locals {
  efs_subscription = templatefile("${local.layers_path}/efs-storage/subscription.yaml.tftpl", {
    operator_channel = "stable"
  })
  efs_cluster_csi_driver = file("${local.layers_path}/efs-storage/cluster-csi-driver.yaml.tftpl")
  efs_storageclass = templatefile("${local.layers_path}/efs-storage/storageclass.yaml.tftpl", {
    efs_file_system_id = var.efs_file_system_id
    storage_class_name = var.efs_storage_class_name
  })
}

#------------------------------------------------------------------------------
# OperatorGroup
#
# On ROSA HCP, openshift-cluster-csi-drivers exists but has no OperatorGroup.
# OLM requires one to create InstallPlans. On Classic it may already exist;
# server_side_apply + force_conflicts handles the idempotent case.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "efs_operatorgroup" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  yaml_body = file("${local.layers_path}/efs-storage/operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_argocd_ready]
}

#------------------------------------------------------------------------------
# Subscription (OLM)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "efs_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  yaml_body = local.efs_subscription

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.efs_operatorgroup]
}

#------------------------------------------------------------------------------
# Wait for EFS CSI Driver Operator
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_efs_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.efs_subscription]
}

#------------------------------------------------------------------------------
# Secret: EFS CSI driver credentials (IRSA role ARN)
#
# The EFS CSI driver controller reads this secret to obtain the IAM role
# for STS token exchange via IRSA.
#------------------------------------------------------------------------------

resource "kubernetes_secret_v1" "efs_csi_credentials" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  metadata {
    name      = "aws-efs-cloud-credentials"
    namespace = "openshift-cluster-csi-drivers"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "efs-storage"
    }
  }

  data = {
    credentials = <<-EOT
      [default]
      sts_regional_endpoints = regional
      role_arn = ${var.efs_role_arn}
      web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.wait_for_efs_operator]
}

#------------------------------------------------------------------------------
# ClusterCSIDriver CR
#
# Tells the operator to deploy and manage the EFS CSI driver pods.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "efs_cluster_csi_driver" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  yaml_body = local.efs_cluster_csi_driver

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_secret_v1.efs_csi_credentials]
}

#------------------------------------------------------------------------------
# Wait for CSI driver to be ready
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_efs_csi_driver" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  create_duration = "60s"

  depends_on = [kubectl_manifest.efs_cluster_csi_driver]
}

#------------------------------------------------------------------------------
# StorageClass: efs-sc
#
# Dynamic provisioning via EFS access points. Each PVC gets its own
# access point with isolated uid/gid permissions.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "efs_storageclass" {
  count = !var.skip_k8s_destroy && var.enable_layer_efs_storage ? 1 : 0

  yaml_body = local.efs_storageclass

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_efs_csi_driver]
}
