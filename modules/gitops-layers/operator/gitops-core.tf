# Terraform owns operators and platform layers. Argo CD owns only explicitly
# delegated workload namespaces. Review docs/GITOPS.md before existing-install upgrades.
locals {
  gitops_channel = lookup(yamldecode(file("${local.layers_path}/gitops/channels.yaml")), "${local.ocp_major_version}.${local.ocp_minor_version}", "unsupported")
  gitops_subscription = templatefile("${local.layers_path}/gitops/subscription.yaml.tftpl", {
    config = var.gitops_operator_config, channel = local.gitops_channel
  })
  gitops_instance = templatefile("${local.layers_path}/gitops/argocd.yaml.tftpl", { config = var.gitops_instance_config })
  gitops_project = templatefile("${local.layers_path}/gitops/project.yaml.tftpl", {
    repo_url    = var.gitops_repo_url, namespace = var.gitops_application.namespace
    view_groups = var.gitops_application.view_groups, sync_groups = var.gitops_application.sync_groups
  })
  gitops_application_manifest = templatefile("${local.layers_path}/gitops/application.yaml.tftpl", {
    repo_url = var.gitops_repo_url, revision = var.gitops_repo_revision
    path     = var.gitops_repo_path, config = var.gitops_application
  })
}

resource "kubectl_manifest" "openshift_gitops_ns" {
  count = 1
  yaml_body = yamlencode({
    apiVersion = "v1", kind = "Namespace"
    metadata = {
      name   = "openshift-gitops"
      labels = { "openshift.io/cluster-monitoring" = "true", "app.kubernetes.io/managed-by" = "terraform" }
    }
  })
  server_side_apply = true
  force_conflicts   = false
  # Namespace deletion would destroy all apps/credentials; retire explicitly.
  apply_only = true
}

resource "kubectl_manifest" "gitops_operator_namespace" {
  count = var.gitops_operator_config.namespace != "openshift-operators" ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "v1", kind = "Namespace"
    metadata   = { name = var.gitops_operator_config.namespace, labels = { "openshift.io/cluster-monitoring" = "true" } }
  })
  server_side_apply = true
  apply_only        = true
}
resource "kubectl_manifest" "gitops_operator_group" {
  count = var.gitops_operator_config.namespace != "openshift-operators" ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "operators.coreos.com/v1", kind = "OperatorGroup"
    metadata   = { name = "openshift-gitops-operator", namespace = var.gitops_operator_config.namespace }
    spec       = { upgradeStrategy = "Default" }
  })
  server_side_apply = true
  depends_on        = [kubectl_manifest.gitops_operator_namespace]
}
resource "kubectl_manifest" "gitops_subscription" {
  count             = 1
  yaml_body         = local.gitops_subscription
  server_side_apply = true
  force_conflicts   = false
  lifecycle {
    precondition {
      condition     = local.gitops_channel != "unsupported"
      error_message = "No verified GitOps stream for this OpenShift minor. Check Red Hat support and update the channel matrix."
    }
  }
  depends_on = [kubectl_manifest.openshift_gitops_ns, kubectl_manifest.gitops_operator_group]
}
resource "time_sleep" "wait_for_gitops_operator" {
  count            = 1
  create_duration  = "120s"
  destroy_duration = "45s"
  depends_on       = [kubectl_manifest.gitops_subscription]
}

# The old argocd_rbac cluster-admin binding is intentionally removed from config:
# Terraform will delete it. Do not preserve an unnecessary administrative grant.
resource "kubectl_manifest" "argocd_instance" {
  count             = 1
  yaml_body         = local.gitops_instance
  server_side_apply = true
  force_conflicts   = false # Explicitly manage the desired ArgoCD CR, not generated operands.
  wait_for {
    field {
      key   = "status.phase"
      value = "Available"
    }
  }
  timeouts {
    create = "30m"
    update = "30m"
  }
  depends_on = [time_sleep.wait_for_gitops_operator]
}
resource "time_sleep" "wait_for_argocd_ready" {
  count           = 1
  create_duration = "10s"
  depends_on      = [kubectl_manifest.argocd_instance]
}
resource "kubectl_manifest" "gitops_default_project" {
  count             = 1
  yaml_body         = file("${local.layers_path}/gitops/default-project.yaml")
  server_side_apply = true
  force_conflicts   = false
  # Retain the deny policy if removing the module, instead of reopening default.
  apply_only = true
  depends_on = [time_sleep.wait_for_argocd_ready]
}
resource "kubectl_manifest" "gitops_workload_namespace" {
  count = var.gitops_application.enabled ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "v1", kind = "Namespace"
    metadata = {
      name = var.gitops_application.namespace
      # Supported operator delegation. Does not grant access to other namespaces.
      labels = { "argocd.argoproj.io/managed-by" = "openshift-gitops" }
    }
  })
  server_side_apply = true
  force_conflicts   = false
  apply_only        = true # Never cascade-delete workloads by toggling an input.
  depends_on        = [time_sleep.wait_for_argocd_ready]
}
resource "kubectl_manifest" "gitops_workload_project" {
  count             = var.gitops_application.enabled ? 1 : 0
  yaml_body         = local.gitops_project
  server_side_apply = true
  force_conflicts   = false
  depends_on        = [kubectl_manifest.gitops_default_project, kubectl_manifest.gitops_workload_namespace]
}
resource "kubectl_manifest" "external_repo_application" {
  count             = var.gitops_application.enabled ? 1 : 0
  yaml_body         = local.gitops_application_manifest
  server_side_apply = true
  force_conflicts   = false
  depends_on        = [kubectl_manifest.gitops_workload_project]
}
