#------------------------------------------------------------------------------
# AutoNode Pool Module Variables
#------------------------------------------------------------------------------

variable "autonode_pools" {
  type = list(object({
    name           = string
    instance_type  = optional(string, "")
    instance_types = optional(list(string), [])
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key           = string
      value         = optional(string, "")
      schedule_type = string
    })), [])
    capacity_type        = optional(string, "on-demand")
    node_class           = optional(string, "default")
    consolidation_policy = optional(string, "WhenEmptyOrUnderutilized")
    consolidate_after    = optional(string, "30s")
    limits               = optional(map(string), {})
    weight               = optional(number, 0)
    expire_after         = optional(string, "720h")
  }))

  description = <<-EOT
    Karpenter NodePool definitions. Supports simple through complex configs:

    Simple (just name + instance_type, everything else defaults):

      autonode_pools = [
        { name = "general", instance_type = "m6a.2xlarge" }
      ]

    Multi-type with limits:

      autonode_pools = [{
        name           = "compute"
        instance_types = ["m6a.2xlarge", "m6a.4xlarge", "m7a.2xlarge"]
        capacity_type  = "spot"
        limits         = { cpu = "64", memory = "256Gi" }
        expire_after   = "168h"
      }]

    GPU with taints, labels, and weight:

      autonode_pools = [{
        name          = "gpu-l40"
        instance_type = "g6e.2xlarge"
        capacity_type = "spot"
        labels        = { "node-role.autonode/gpu" = "" }
        taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
        weight        = 10
      }]

    Fields:
      instance_type  - single instance type (use this OR instance_types)
      instance_types - multiple types; Karpenter picks best fit
      capacity_type  - "on-demand" (default) or explicit "spot"
      node_class     - EC2NodeClass name (default: "default")
      labels         - pod template labels (reserved domains rejected)
      taints         - list of {key, value (optional), schedule_type}
      limits         - max resources pool can provision, e.g. {cpu="100"}
      weight         - priority between pools; higher = preferred (default 0)
      expire_after   - node TTL before replacement (default "720h" / 30 days)
      consolidation_policy - "WhenEmptyOrUnderutilized" (default) or "WhenEmpty"
      consolidate_after    - delay before consolidation (default "30s")
  EOT

  validation {
    condition = alltrue([for pool in var.autonode_pools :
      (length(pool.instance_types) > 0) != (pool.instance_type != "") &&
      contains(["on-demand", "spot"], pool.capacity_type) &&
      alltrue([for key in keys(pool.labels) : !can(regex("(kubernetes[.]io|k8s[.]io)/", key))])
    ])
    error_message = "Choose exactly one instance_type or nonempty instance_types, a valid capacity type, and custom-domain labels; labels are never silently discarded."
  }
  default = []
}

variable "node_class_group" {
  type        = string
  description = "NodePool reference group for the provider-managed EC2NodeClass."
  default     = "karpenter.k8s.aws"
}
variable "node_class_kind" {
  type        = string
  description = "NodePools reference EC2NodeClass, including classes derived from custom OpenshiftEC2NodeClass objects."
  default     = "EC2NodeClass"
}
