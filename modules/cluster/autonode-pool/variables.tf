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
    capacity_type        = optional(string, "spot")
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
      capacity_type  - "spot" (default) or "on-demand"
      node_class     - EC2NodeClass name (default: "default")
      labels         - pod template labels (kubernetes.io domain auto-filtered)
      taints         - list of {key, value (optional), schedule_type}
      limits         - max resources pool can provision, e.g. {cpu="100"}
      weight         - priority between pools; higher = preferred (default 0)
      expire_after   - node TTL before replacement (default "720h" / 30 days)
      consolidation_policy - "WhenEmptyOrUnderutilized" (default) or "WhenEmpty"
      consolidate_after    - delay before consolidation (default "30s")
  EOT

  default = []
}

variable "node_class_group" {
  type        = string
  description = <<-EOT
    API group for the nodeClassRef in NodePool specs.
    ROSA HCP AutoNode private preview requires karpenter.k8s.aws (EC2NodeClass),
    NOT karpenter.hypershift.openshift.io (OpenshiftEC2NodeClass).
    See AutoNode FAQ #7: NodePools reference EC2NodeClass during private preview.
  EOT
  default     = "karpenter.k8s.aws"
}

variable "node_class_kind" {
  type        = string
  description = <<-EOT
    Kind for the nodeClassRef in NodePool specs.
    ROSA HCP AutoNode private preview requires EC2NodeClass.
    OpenshiftEC2NodeClass is for creating custom node classes, but NodePools
    must reference the corresponding EC2NodeClass (managed by HyperShift).
  EOT
  default     = "EC2NodeClass"
}

variable "skip_k8s_destroy" {
  type        = bool
  description = "Set true before terraform destroy to skip K8s resource deletion."
  default     = false
}
