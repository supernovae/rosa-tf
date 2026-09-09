terraform { required_version = ">= 1.16.1, < 2.0.0" }
variable "openshift_version" { default = "4.22.0" }
variable "enable_layer_oadp" { default = false }
variable "virtualization_enabled" { default = false }
variable "region" { default = "us-east-1" }
variable "role_arn" { default = "arn:aws:iam::123456789012:role/backup-role" }
locals {
  path    = "${path.module}/../../gitops-layers/layers/oadp"
  release = yamldecode(file("${local.path}/release.yaml"))
  stream = try(one([for stream, release in local.release.streams :
    stream if contains(release.openshift_minors, tonumber(split(".", var.openshift_version)[1]))
  ]), "")
  manifests = {
    subscription = yamldecode(templatefile("${local.path}/subscription.yaml.tftpl", {
      config = var.oadp_config, role_arn = var.role_arn
    }))
    dpa = yamldecode(templatefile("${local.path}/dataprotectionapplication.yaml.tftpl", {
      bucket_name            = "test-backup-bucket", region = var.region, config = var.oadp_config
      virtualization_enabled = var.virtualization_enabled || var.oadp_config.virtualization_enabled
      node_agent_tolerations = var.oadp_config.node_agent_tolerations
    }))
    schedule = yamldecode(templatefile("${local.path}/schedule-nightly.yaml.tftpl", {
      cluster_name = "test", backup_retention_days = 30, config = var.oadp_config
    }))
    snapshot_class = yamldecode(file("${local.path}/netapp-volumesnapshotclass.yaml"))
  }
}
output "manifests" { value = local.manifests }
output "stream" { value = local.stream }
