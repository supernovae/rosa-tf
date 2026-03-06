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
    storage_class_name         = var.monitoring_storage_class
  })
  monitoring_logforwarder = templatefile("${local.layers_path}/monitoring/clusterlogforwarder-observability.yaml.tftpl", {
    cluster_name = var.cluster_name
  })

  # LokiStack with optional node placement (nodeSelector + tolerations).
  # The template also contains an S3 Secret document which we create
  # separately via kubernetes_secret_v1, so extract only the first YAML doc.
  monitoring_lokistack_full = templatefile("${local.layers_path}/monitoring/lokistack-observability.yaml.tftpl", {
    loki_size            = var.monitoring_loki_size
    bucket_name          = var.monitoring_bucket_name
    bucket_region        = var.aws_region
    role_arn             = var.monitoring_role_arn
    retention_days       = var.monitoring_retention_days
    storage_class        = var.monitoring_storage_class
    node_selector        = var.monitoring_node_selector
    tolerations          = var.monitoring_tolerations
    ingestion_rate       = var.monitoring_loki_ingestion_rate
    ingestion_burst_size = var.monitoring_loki_ingestion_burst_size
  })
  monitoring_lokistack = element(split("\n---\n", local.monitoring_lokistack_full), 1)
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

# openshift-logging namespace may already exist on fresh clusters (created by
# OpenShift). Using kubectl_manifest with server_side_apply to be idempotent.
resource "kubectl_manifest" "monitoring_logging_ns" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "openshift-logging"
      labels = {
        "openshift.io/cluster-monitoring" = "true"
        "app.kubernetes.io/managed-by"    = "terraform"
        "app.kubernetes.io/part-of"       = "rosa-gitops-layers"
        "app.kubernetes.io/component"     = "monitoring"
      }
    }
  })

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_argocd_ready]
}

# openshift-operators-redhat namespace may already exist on fresh clusters.
resource "kubectl_manifest" "monitoring_operators_redhat_ns" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "openshift-operators-redhat"
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
        "app.kubernetes.io/component"  = "monitoring"
      }
    }
  })

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_logging_ns]
}

#------------------------------------------------------------------------------
# OperatorGroups and Subscriptions
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_operatorgroup_logging" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/operatorgroup-logging.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_logging_ns]
}

resource "kubectl_manifest" "monitoring_operatorgroup_operators_redhat" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = file("${local.layers_path}/monitoring/operatorgroup-operators-redhat.yaml")

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.monitoring_operators_redhat_ns]
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

  data = {
    bucketnames = var.monitoring_bucket_name
    region      = var.aws_region
    role_arn    = var.monitoring_role_arn
  }

  depends_on = [kubectl_manifest.monitoring_logging_ns]
}

#------------------------------------------------------------------------------
# LokiStack
#------------------------------------------------------------------------------

resource "kubectl_manifest" "monitoring_lokistack" {
  count = !var.skip_k8s_destroy && var.enable_layer_monitoring ? 1 : 0

  yaml_body = local.monitoring_lokistack

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
