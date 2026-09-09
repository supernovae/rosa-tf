# Shared by all ROSA roots. Confirm platform/region/storage support before enabling.
variable "virt_config" {
  description = "Virtualization lifecycle, placement and NetApp integration. See docs/VIRTUALIZATION.md."
  type = object({
    platform_support_confirmed = optional(bool, false)
    install_plan_approval      = optional(string, "Automatic")
    catalog_source             = optional(string, "redhat-operators")
    catalog_namespace          = optional(string, "openshift-marketplace")
    common_boot_images         = optional(bool, false)
    infra_node_selector        = optional(map(string), {})
    infra_tolerations = optional(list(object({
      key      = string
      operator = optional(string, "Equal")
      value    = optional(string, "")
      effect   = string
    })), [])
    netapp_storage_profiles = optional(bool, true)
  })
  default = {}
  validation {
    condition     = contains(["Automatic", "Manual"], var.virt_config.install_plan_approval)
    error_message = "Virtualization approval must be Automatic or Manual."
  }
  validation {
    condition     = var.virt_config.catalog_source != "" && var.virt_config.catalog_namespace != ""
    error_message = "Provide the operator catalog source and namespace."
  }
  validation {
    condition = alltrue([for t in var.virt_config.infra_tolerations :
      contains(["Equal", "Exists"], t.operator) && contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect) &&
      (t.operator != "Exists" || t.value == "")
    ])
    error_message = "Invalid infrastructure toleration operator, effect or Exists value."
  }
}
