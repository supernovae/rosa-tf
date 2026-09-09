variable "oadp_config" {
  description = "Supported OADP lifecycle, CSI data protection and explicit workload scheduling. See docs/OADP.md."
  type = object({
    support_confirmed         = optional(bool, false)
    install_plan_approval     = optional(string, "Manual")
    catalog_source            = optional(string, "redhat-operators")
    catalog_namespace         = optional(string, "openshift-marketplace")
    virtualization_enabled    = optional(bool, false)
    filesystem_backup_enabled = optional(bool, false)
    schedule_enabled          = optional(bool, false)
    schedule_paused           = optional(bool, true)
    schedule                  = optional(string, "0 2 * * *")
    included_namespaces       = optional(list(string), [])
    node_agent_tolerations = optional(list(object({
      key      = string
      operator = optional(string, "Equal")
      value    = optional(string, "")
      effect   = string
    })), [])
  })
  default = {}
  validation {
    condition = !var.enable_layer_oadp || (
      var.oadp_config.support_confirmed &&
      try(tonumber(split(".", var.openshift_version)[0]), 0) == 4 &&
      contains([19, 20, 21, 22], try(tonumber(split(".", var.openshift_version)[1]), 0))
    )
    error_message = "Set oadp_config.support_confirmed=true after review. OADP 1.5 supports OpenShift 4.19–4.21 and OADP 1.6 supports 4.22. Resolve the platform upgrade before enabling OADP on 4.18; this also gates AWS-only provisioning."
  }
  validation {
    condition = (contains(["Manual", "Automatic"], var.oadp_config.install_plan_approval) &&
    var.oadp_config.catalog_source != "" && var.oadp_config.catalog_namespace != "")
    error_message = "Provide a valid approval strategy and nonempty OADP catalog source/namespace."
  }
  validation {
    condition = alltrue([for ns in var.oadp_config.included_namespaces :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", ns)) && length(ns) <= 63 &&
      !startswith(ns, "openshift") && !startswith(ns, "kube-") &&
      !contains(["default", "trident"], ns)
    ]) && length(distinct(var.oadp_config.included_namespaces)) == length(var.oadp_config.included_namespaces)
    error_message = "Use unique, explicit workload namespaces; wildcard and system/platform namespaces are not allowed."
  }
  validation {
    condition     = !var.oadp_config.schedule_enabled || length(var.oadp_config.included_namespaces) > 0
    error_message = "An enabled backup schedule requires explicit workload namespaces."
  }
  validation {
    condition = (length(regexall("[^ ]+", trimspace(var.oadp_config.schedule))) == 5 &&
    !strcontains(var.oadp_config.schedule, "\n"))
    error_message = "Provide a five-field UTC cron expression; validate actual timing before unpausing."
  }
  validation {
    condition = alltrue([for t in var.oadp_config.node_agent_tolerations :
      contains(["Equal", "Exists"], t.operator) && contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect) &&
      (t.operator != "Exists" || t.value == "")
    ])
    error_message = "Invalid node-agent toleration."
  }
}
