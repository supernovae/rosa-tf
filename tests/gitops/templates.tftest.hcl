run "safe_defaults" {
  command = plan
  assert {
    condition     = !var.gitops_application.enabled
    error_message = "Workload sync must be an explicit opt-in."
  }
  assert {
    condition     = local.manifests.argocd.spec.disableAdmin && local.manifests.argocd.spec.defaultClusterScopedRoleDisabled && local.manifests.argocd.spec.rbac.defaultPolicy == "role:no-access"
    error_message = "Disable local admin, implicit login privileges and default cluster-wide role grants."
  }
  assert {
    condition     = !contains(keys(local.manifests.application.spec.syncPolicy), "automated") && length(local.manifests.application.metadata.finalizers) == 0
    error_message = "Default app sync is manual and app removal must not cascade."
  }
  assert {
    condition     = length(local.manifests.project.spec.clusterResourceWhitelist) == 0 && length(local.manifests.default_project.spec.sourceRepos) == 0 && length(local.manifests.default_project.spec.destinations) == 0
    error_message = "Do not permit cluster resources or the default-project bypass."
  }
  assert {
    condition     = local.manifests.subscription.spec.channel == "gitops-1.21"
    error_message = "4.18 should use the current compatible GitOps stream."
  }
  assert {
    condition     = local.manifests.subscription.spec.config.env[0].name == "ARGOCD_CLUSTER_CONFIG_NAMESPACES" && local.manifests.subscription.spec.config.env[0].value == "" && local.manifests.argocd.spec.extraConfig["resource.respectRBAC"] == "normal"
    error_message = "Namespace RBAC must also use a namespace-scoped cache, without implicit cluster-config instances."
  }
}
run "controlled_ha_automation" {
  command = plan
  variables {
    gitops_instance_config = { ha_enabled = true }
    gitops_application     = { enabled = true, automated = true, self_heal = true }
    gitops_operator_config = { source = "approved-mirror", install_plan_approval = "Manual" }
  }
  assert {
    condition     = local.manifests.argocd.spec.ha.enabled && local.manifests.argocd.spec.server.replicas == 2 && local.manifests.argocd.spec.repo.replicas == 2
    error_message = "HA needs redundant server/repo components."
  }
  assert {
    condition     = !local.manifests.application.spec.syncPolicy.automated.prune && !local.manifests.application.spec.syncPolicy.automated.allowEmpty && contains(local.manifests.application.spec.syncPolicy.syncOptions, "FailOnSharedResource=true")
    error_message = "Automation must retain prune/empty safeguards and shared-resource protection."
  }
}
run "older_cluster_direct_oidc" {
  command = plan
  variables {
    openshift_minor        = "4.16"
    gitops_instance_config = { oidc_config = "name: Approved SSO\nissuer: https://id.example.test\nclientID: gitops\nclientSecret: $oidc-client-secret:clientSecret\n" }
  }
  assert {
    condition     = local.manifests.subscription.spec.channel == "gitops-1.20" && !contains(keys(local.manifests.argocd.spec), "sso")
    error_message = "Older minors need compatible GitOps and direct OIDC must not also configure Dex."
  }
}
run "reject_system_namespace" {
  command = plan
  variables { gitops_application = { enabled = true, namespace = "openshift-gitops" } }
  expect_failures = [var.gitops_application]
}
run "reject_mutable_auto_revision" {
  command = plan
  variables {
    gitops_application   = { enabled = true, automated = true }
    gitops_repo_revision = "main"
  }
  expect_failures = [var.gitops_application]
}
run "reject_unset_repository" {
  command = plan
  variables {
    gitops_application = { enabled = true }
    gitops_repo_url    = ""
  }
  expect_failures = [var.gitops_application]
}
run "reject_repository_credentials" {
  command = plan
  variables {
    gitops_application = { enabled = true }
    gitops_repo_url    = "https://token@git.example.com/team/workloads.git"
  }
  expect_failures = [var.gitops_application]
}
run "reject_rbac_injection" {
  command = plan
  variables { gitops_application = { view_groups = ["*, role:admin"] } }
  expect_failures = [var.gitops_application]
}
run "reject_inline_oidc_secret" {
  command = plan
  variables {
    gitops_instance_config = { oidc_config = "issuer: https://id.example.test\nclientID: gitops\nclientSecret: not-a-secret-reference\n" }
  }
  expect_failures = [var.gitops_instance_config]
}
run "reject_prune_without_automation" {
  command = plan
  variables { gitops_application = { prune = true } }
  expect_failures = [var.gitops_application]
}
run "project_group_permissions" {
  command = plan
  variables {
    gitops_application = { view_groups = ["team-view"], sync_groups = ["team-sync"] }
  }
  assert {
    condition     = local.manifests.project.spec.roles[0].groups == ["team-view"] && local.manifests.project.spec.roles[1].groups == ["team-sync"]
    error_message = "Map workload viewer and sync groups without administrative privileges."
  }
}
run "public_oidc_client" {
  command = plan
  variables {
    gitops_instance_config = { oidc_config = "issuer: https://id.example.test\nclientID: public-gitops\n" }
  }
  assert {
    condition     = !contains(keys(local.manifests.argocd.spec), "sso")
    error_message = "A supported public OIDC client need not contain a client secret."
  }
}
run "reject_duplicate_namespace_owner" {
  command = plan
  variables { gitops_operator_config = { namespace = "openshift-gitops" } }
  expect_failures = [var.gitops_operator_config]
}
