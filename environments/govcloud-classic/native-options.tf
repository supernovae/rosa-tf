# Canonical native options for classic; root copies are checked by the RHCS audit.
variable "cluster_options" {
  description = "Native RHCS options using provider names/types. Creation-only fields and regional eligibility remain enforced by RHCS; see docs/RHCS-CAPABILITIES.md."
  type = object({
    trust_policy_external_id            = optional(string)
    base_dns_domain                     = optional(string)
    channel                             = optional(string)
    destroy_timeout                     = optional(number)
    domain_prefix                       = optional(string)
    max_cluster_wait_timeout_in_minutes = optional(number)
    private_hosted_zone = optional(object({
      id       = string
      role_arn = string
    }))
    properties = optional(map(string), {})
  })
  default = {}
  validation {
    condition     = var.cluster_options.destroy_timeout == null ? true : var.cluster_options.destroy_timeout > 0 && floor(var.cluster_options.destroy_timeout) == var.cluster_options.destroy_timeout
    error_message = "destroy_timeout must be positive whole minutes; destroy waiting cannot be disabled."
  }
  validation {
    condition     = !contains(keys(var.cluster_options.properties), "rosa_creator_arn") && !contains(keys(var.cluster_options.properties), "zero_egress")
    error_message = "Use dedicated identity/zero-egress inputs, not reserved OCM properties."
  }
}
