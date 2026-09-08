terraform {
  required_version = ">= 1.16.1, < 2.0.0"
}
variable "region" { default = "us-east-1" }
variable "arm" { default = false }
locals {
  path        = "${path.module}/../../gitops-layers/layers/monitoring"
  channels    = yamldecode(file("${local.path}/logging-channels.yaml"))
  selector    = var.arm ? { "kubernetes.io/arch" = "arm64", "node-role.kubernetes.io/monitoring" = "" } : {}
  tolerations = var.arm ? [{ key = "workload", operator = "Equal", value = "monitoring", effect = "PreferNoSchedule" }] : []
  loki = yamldecode(element(split("\n---\n", templatefile("${local.path}/lokistack-observability.yaml.tftpl", {
    loki_size      = "1x.extra-small", bucket_name = "test-loki", bucket_region = var.region
    role_arn       = "arn:${startswith(var.region, "us-gov-") ? "aws-us-gov" : "aws"}:iam::123456789012:role/loki"
    retention_days = 7, storage_class = "gp3-csi", node_selector = local.selector
    tolerations    = local.tolerations, ingestion_rate = 10, ingestion_burst_size = 20
  })), 1))
  workload = yamldecode(templatefile("${local.path}/user-workload-monitoring-config.yaml.tftpl", {
    retention_days = 7, storage_size = "100Gi", storage_class = "gp3-csi"
    node_selector  = local.selector, tolerations = local.tolerations
  }))
  workload_config = yamldecode(local.workload.data["config.yaml"])
  manifests = {
    loki          = local.loki
    forwarder     = yamldecode(templatefile("${local.path}/clusterlogforwarder-observability.yaml.tftpl", { cluster_name = "test" }))
    logging_ui    = yamldecode(file("${local.path}/uiplugin-logging.yaml"))
    monitoring_ui = yamldecode(file("${local.path}/uiplugin-monitoring.yaml"))
  }
}
output "manifests" { value = local.manifests }
