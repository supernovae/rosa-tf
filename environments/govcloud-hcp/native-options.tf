# Canonical native options for hcp; root copies are checked by the RHCS audit.
variable "cluster_options" {
  description = "Native RHCS options using provider names/types. Creation-only fields and regional eligibility remain enforced by RHCS; see docs/RHCS-CAPABILITIES.md."
  type = object({
    trust_policy_external_id          = optional(string)
    audit_log_arn                     = optional(string)
    aws_additional_allowed_principals = optional(list(string))
    base_dns_domain                   = optional(string)
    channel                           = optional(string)
    destroy_timeout                   = optional(number)
    domain_prefix                     = optional(string)
    log_forwarders_at_cluster_creation = optional(list(object({
      applications = optional(list(string))
      cloudwatch = optional(object({
        log_distribution_role_arn = string
        log_group_name            = string
      }))
      groups = optional(list(object({
        id      = string
        version = optional(string)
      })))
      s3 = optional(object({
        bucket_name   = string
        bucket_prefix = optional(string)
      }))
    })))
    max_hcp_cluster_wait_timeout_in_minutes = optional(number)
    max_machinepool_wait_timeout_in_minutes = optional(number)
    proxy = optional(object({
      additional_trust_bundle = optional(string)
      http_proxy              = optional(string)
      https_proxy             = optional(string)
      no_proxy                = optional(string)
    }))
    registry_config = optional(object({
      additional_trusted_ca = optional(map(string))
      allowed_registries_for_import = optional(list(object({
        domain_name = optional(string)
        insecure    = optional(bool)
      })))
      platform_allowlist_id = optional(string)
      registry_sources = optional(object({
        allowed_registries  = optional(list(string))
        blocked_registries  = optional(list(string))
        insecure_registries = optional(list(string))
      }))
    }))
    shared_vpc = optional(object({
      ingress_private_hosted_zone_id                = string
      internal_communication_private_hosted_zone_id = optional(string)
      route53_role_arn                              = string
      vpce_role_arn                                 = string
    }))
    spot_termination_queue_url = optional(string)
    worker_disk_size           = optional(number)
    autoscaling_enabled        = optional(bool)
    min_replicas               = optional(number)
    max_replicas               = optional(number)
    properties                 = optional(map(string), {})
  })
  validation {
    condition     = try(alltrue([for registry in coalesce(var.cluster_options.registry_config.allowed_registries_for_import, []) : !coalesce(registry.insecure, false)]), true) && try(length(coalesce(var.cluster_options.registry_config.registry_sources.insecure_registries, [])) == 0, true)
    error_message = "Registry TLS verification cannot be disabled; supply additional_trusted_ca instead."
  }
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
