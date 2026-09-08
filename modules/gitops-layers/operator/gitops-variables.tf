# Shared GitOps contract: keep this file aligned in the operator and four roots.
variable "gitops_operator_config" {
  type = object({
    namespace             = optional(string, "openshift-gitops-operator")
    source                = optional(string, "redhat-operators")
    source_namespace      = optional(string, "openshift-marketplace")
    install_plan_approval = optional(string, "Automatic")
  })
  default     = {}
  description = "Supported OLM installation. Existing global installs must explicitly retain openshift-operators until a planned namespace migration."
  validation {
    condition     = contains(["Automatic", "Manual"], var.gitops_operator_config.install_plan_approval)
    error_message = "Operator approval must be Automatic or Manual."
  }
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gitops_operator_config.namespace)) && length(var.gitops_operator_config.namespace) <= 63 && !contains(["openshift-gitops", "default", "kube-system", var.terraform_sa_namespace], var.gitops_operator_config.namespace)
    error_message = "Use a dedicated operator namespace (or openshift-operators for migration), separate from the operand and Terraform identity namespaces."
  }
}
variable "gitops_instance_config" {
  type = object({
    ha_enabled    = optional(bool, false)
    admin_enabled = optional(bool, false)
    admin_groups  = optional(list(string), ["system:cluster-admins", "cluster-admins"])
    oidc_config   = optional(string, null)
  })
  default     = {}
  description = "OpenShift OAuth by default; optional direct OIDC configuration must reference external Secrets, not inline client secrets. Enable HA with adequate node capacity."
  validation {
    condition     = length(var.gitops_instance_config.admin_groups) > 0 && alltrue([for group in var.gitops_instance_config.admin_groups : can(regex("^[A-Za-z0-9:_./@-]+$", group))])
    error_message = "Provide explicit administrative groups without Casbin delimiters, whitespace, or wildcard characters."
  }
  validation {
    condition = var.gitops_instance_config.oidc_config == null || try(
      startswith(yamldecode(var.gitops_instance_config.oidc_config).issuer, "https://") &&
      length(yamldecode(var.gitops_instance_config.oidc_config).clientID) > 0 &&
      !try(yamldecode(var.gitops_instance_config.oidc_config).insecureSkipVerify, false) &&
      (try(yamldecode(var.gitops_instance_config.oidc_config).clientSecret, null) == null ? true :
      startswith(yamldecode(var.gitops_instance_config.oidc_config).clientSecret, "$")),
    false)
    error_message = "Direct OIDC must be valid YAML with an HTTPS issuer/clientID, verified TLS and a Secret reference (not an inline clientSecret)."
  }
}
variable "gitops_application" {
  type = object({
    enabled     = optional(bool, false)
    namespace   = optional(string, "gitops-apps")
    automated   = optional(bool, false)
    prune       = optional(bool, false)
    self_heal   = optional(bool, false)
    view_groups = optional(list(string), [])
    sync_groups = optional(list(string), [])
  })
  default     = {}
  description = "Explicit opt-in for one namespace-scoped workload Application. Terraform retains ownership of platform layers."
  validation {
    condition     = alltrue([for group in concat(var.gitops_application.view_groups, var.gitops_application.sync_groups) : can(regex("^[A-Za-z0-9:_./@-]+$", group))]) && var.gitops_application.namespace != var.gitops_operator_config.namespace
    error_message = "Use explicit group names without Casbin delimiters/wildcards and keep workload/operator namespaces separate."
  }
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gitops_application.namespace)) && length(var.gitops_application.namespace) <= 63 && !startswith(var.gitops_application.namespace, "openshift") && !startswith(var.gitops_application.namespace, "kube-") && !contains(["default", "rosa-terraform", var.terraform_sa_namespace], var.gitops_application.namespace)
    error_message = "Use a dedicated non-system application namespace, not an Argo CD or Terraform identity namespace."
  }
  validation {
    condition     = !var.gitops_application.enabled || try(can(regex("^https://[^/@?#]+/[^?#]+$", var.gitops_repo_url)) && !strcontains(var.gitops_repo_url, "*"), false)
    error_message = "An enabled Application requires an explicit HTTPS repository URL without credentials, query strings or wildcards."
  }
  validation {
    condition     = !var.gitops_application.automated || try(can(regex("^[0-9a-f]{40}$", var.gitops_repo_revision)), false)
    error_message = "Automatic sync requires a reviewed immutable 40-character Git commit SHA."
  }
  validation {
    condition     = var.gitops_application.automated || (!var.gitops_application.prune && !var.gitops_application.self_heal)
    error_message = "prune/self_heal require automated=true; all are off by default."
  }
}
variable "gitops_create_legacy_token" {
  type        = bool
  default     = false
  description = "Explicit compatibility opt-in for a long-lived cluster-admin SA Secret. Prefer short-lived runner credentials; migrate authentication before turning this off on an existing installation."
}
