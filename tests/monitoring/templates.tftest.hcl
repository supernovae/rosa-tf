run "supported_streams" {
  command = plan
  assert {
    condition     = local.channels["4.18"] == "stable-6.2" && local.channels["4.19"] == "stable-6.5" && local.channels["4.20"] == "stable-6.6"
    error_message = "Do not upgrade 4.18 to an expired/noncompatible stream or pair mismatched Loki/Logging streams."
  }
  assert {
    condition     = yamldecode(yamldecode(file("${local.path}/cluster-monitoring-config.yaml")).data["config.yaml"]) == { enableUserWorkload = true }
    error_message = "Do not override ROSA platform monitoring configuration."
  }
  assert {
    condition     = local.loki.spec.storage.secret.credentialMode == "token" && local.loki.spec.storage.schemas[0].version == "v13"
    error_message = "Loki must use explicit short-lived credentials and TSDB v13."
  }
  assert {
    condition     = local.workload_config.prometheus.retention == "7d" && local.workload_config.alertmanager.enableAlertmanagerConfig
    error_message = "User metrics must have retention and namespace-scoped alert routing."
  }
}
run "govcloud_arm" {
  command = plan
  variables {
    region = "us-gov-west-1"
    arm    = true
  }
  assert {
    condition     = alltrue([for component in values(local.loki.spec.template) : component.nodeSelector["kubernetes.io/arch"] == "arm64" && component.tolerations[0].effect == "PreferNoSchedule"])
    error_message = "Every Loki component must honor ARM placement."
  }
  assert {
    condition     = alltrue([for component in values(local.workload_config) : component.nodeSelector["kubernetes.io/arch"] == "arm64"])
    error_message = "User Prometheus, Thanos Ruler and Alertmanager must honor placement."
  }
}
