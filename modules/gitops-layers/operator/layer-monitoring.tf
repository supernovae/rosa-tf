#------------------------------------------------------------------------------
# Layer: Monitoring (Prometheus + Loki + Cluster Logging)
#
# Installs the OpenShift monitoring stack: cluster-monitoring-config,
# Loki Operator, Cluster Logging Operator, Cluster Observability Operator,
# and configures log forwarding to Loki with S3 storage.
#
# Dependencies:
#   - S3 bucket from gitops-layers/monitoring module
#   - IAM role with OIDC trust from gitops-layers/monitoring module
#------------------------------------------------------------------------------

locals {
  # Monitoring templates
  monitoring_subscription_loki = templatefile("${local.layers_path}/monitoring/subscription-loki.yaml.tftpl", {
    operator_channel = local.operator_channels.loki
  })
  monitoring_subscription_logging = templatefile("${local.layers_path}/monitoring/subscription-logging.yaml.tftpl", {
    operator_channel = local.operator_channels.cluster_logging
  })
  monitoring_cluster_config = templatefile("${local.layers_path}/monitoring/cluster-monitoring-config.yaml.tftpl", {
    prometheus_retention_hours = var.monitoring_retention_days * 24
    prometheus_retention_days  = var.monitoring_retention_days
    prometheus_storage_size    = var.monitoring_prometheus_storage_size
    storage_class_name        = var.monitoring_storage_class
  })
  monitoring_logforwarder = templatefile("${local.layers_path}/monitoring/clusterlogforwarder-observability.yaml.tftpl", {
    cluster_name = var.cluster_name
  })
}

#------------------------------------------------------------------------------
# Cluster Monitoring Config
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_cluster_config" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = local.monitoring_cluster_config

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_argocd_ready]
}

#------------------------------------------------------------------------------
# PrometheusRules (HCP only - Classic has SRE-managed openshift-monitoring)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_prometheus_rules" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring && var.cluster_type == "hcp" ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/prometheus-rules.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_cluster_config]
}

#------------------------------------------------------------------------------
# Namespaces
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "monitoring_logging" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  metadata {
    name = "openshift-logging"

    labels = {
      "openshift.io/cluster-monitoring" = "true"
      "app.kubernetes.io/managed-by"    = "terraform"
      "app.kubernetes.io/part-of"       = "rosa-gitops-layers"
      "app.kubernetes.io/component"     = "monitoring"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.wait_for_argocd_ready]
}

resource "kubernetes_namespace_v1" "monitoring_operators_redhat" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  metadata {
    name = "openshift-operators-redhat"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "monitoring"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [kubernetes_namespace_v1.monitoring_logging]
}

#------------------------------------------------------------------------------
# OperatorGroups and Subscriptions
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_operatorgroup_logging" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/operatorgroup-logging.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_namespace_v1.monitoring_logging]
}

resource "kubectl_manifest" "monitoring_operatorgroup_operators_redhat" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/operatorgroup-operators-redhat.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_namespace_v1.monitoring_operators_redhat]
}

resource "kubectl_manifest" "monitoring_loki_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = local.monitoring_subscription_loki

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_operatorgroup_operators_redhat]
}

resource "kubectl_manifest" "monitoring_logging_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = local.monitoring_subscription_logging

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_operatorgroup_logging]
}

#------------------------------------------------------------------------------
# Wait for Loki Operator
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_loki_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.monitoring_loki_subscription]
}

#------------------------------------------------------------------------------
# Loki S3 Secret
#------------------------------------------------------------------------------

resource "kubernetes_secret_v1" "monitoring_loki_s3" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  metadata {
    name      = "logging-loki-s3"
    namespace = "openshift-logging"
  }

  string_data = {
    bucketnames = var.monitoring_bucket_name
    region      = var.aws_region
    role_arn    = var.monitoring_role_arn
  }

  depends_on = [kubernetes_namespace_v1.monitoring_logging]
}

#------------------------------------------------------------------------------
# LokiStack
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_lokistack" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = <<-YAML
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: ${var.monitoring_loki_size}
  storage:
    schemas:
      - version: v13
        effectiveDate: "2024-10-15"
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: ${var.monitoring_storage_class}
  tenants:
    mode: openshift-logging
  limits:
    global:
      retention:
        days: ${var.monitoring_retention_days}
        streams:
          - selector: '{log_type="infrastructure"}'
            priority: 1
            days: ${var.monitoring_retention_days}
          - selector: '{log_type="application"}'
            priority: 1
            days: ${var.monitoring_retention_days}
          - selector: '{log_type="audit"}'
            priority: 1
            days: ${var.monitoring_retention_days}
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    time_sleep.wait_for_loki_operator,
    kubernetes_secret_v1.monitoring_loki_s3,
  ]
}

#------------------------------------------------------------------------------
# Wait for Logging Operator
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_logging_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.monitoring_logging_subscription]
}

#------------------------------------------------------------------------------
# ServiceAccount and RBAC
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_serviceaccount" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/serviceaccount-logcollector.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    time_sleep.wait_for_logging_operator,
    kubectl_manifest.monitoring_lokistack,
  ]
}

resource "kubectl_manifest" "monitoring_rbac_application" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/clusterlogging-rbac-application.yaml.tftpl")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_serviceaccount]
}

resource "kubectl_manifest" "monitoring_rbac_infrastructure" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/clusterlogging-rbac-infrastructure.yaml.tftpl")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_rbac_application]
}

resource "kubectl_manifest" "monitoring_rbac_audit" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/clusterlogging-rbac-audit.yaml.tftpl")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_rbac_infrastructure]
}

resource "kubectl_manifest" "monitoring_loki_writer_role" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/clusterrole-loki-writer.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_rbac_audit]
}

resource "kubectl_manifest" "monitoring_loki_writer_binding" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/clusterrolebinding-loki-writer.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_loki_writer_role]
}

#------------------------------------------------------------------------------
# ClusterLogForwarder
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_logforwarder" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = local.monitoring_logforwarder

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    time_sleep.wait_for_logging_operator,
    kubectl_manifest.monitoring_lokistack,
    kubectl_manifest.monitoring_serviceaccount,
    kubectl_manifest.monitoring_rbac_application,
    kubectl_manifest.monitoring_rbac_infrastructure,
    kubectl_manifest.monitoring_rbac_audit,
    kubectl_manifest.monitoring_loki_writer_binding,
  ]
}

#------------------------------------------------------------------------------
# Collector ServiceMonitor
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_servicemonitor" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/servicemonitor-collector.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_logforwarder]
}

#------------------------------------------------------------------------------
# COO Subscription (Cluster Observability Operator)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_coo_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/subscription-coo.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_argocd_ready]
}

resource "time_sleep" "wait_for_coo_operator" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  create_duration = "90s"

  depends_on = [kubectl_manifest.monitoring_coo_subscription]
}

#------------------------------------------------------------------------------
# Wait for LokiStack Ready
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_lokistack_ready" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  create_duration = "60s"

  depends_on = [kubectl_manifest.monitoring_lokistack]
}

#------------------------------------------------------------------------------
# Logging UIPlugin (Observe > Logs in Console)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_uiplugin" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/uiplugin-logging.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    time_sleep.wait_for_coo_operator,
    time_sleep.wait_for_lokistack_ready,
  ]
}
