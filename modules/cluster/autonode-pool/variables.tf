#------------------------------------------------------------------------------
# AutoNode Pool Module Variables
#------------------------------------------------------------------------------

variable "autonode_pools" {
  type = list(object({
    name          = string
    instance_type = string
    labels        = optional(map(string), {})
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string
    })), [])
    capacity_type        = optional(string, "spot")
    node_class           = optional(string, "default")
    consolidation_policy = optional(string, "WhenEmptyOrUnderutilized")
  }))

  description = <<-EOT
    List of Karpenter NodePool definitions. Format mirrors machine_pools:

      autonode_pools = [
        {
          name          = "gpu-spot"
          instance_type = "g6e.2xlarge"
          capacity_type = "spot"          # "spot" or "on-demand"
          node_class    = "default"       # OpenshiftEC2NodeClass name
          labels = {
            "node-role.kubernetes.io/gpu" = ""
          }
          taints = [{
            key           = "nvidia.com/gpu"
            value         = "true"
            schedule_type = "NoSchedule"  # maps to Karpenter effect
          }]
        }
      ]

    capacity_type controls Spot vs On-Demand pricing. Karpenter will wait
    for Spot capacity if unavailable; add "on-demand" as a separate pool
    for fallback.

    consolidation_policy controls when Karpenter consolidates (disrupts)
    nodes. Default "WhenEmptyOrUnderutilized"; set "WhenEmpty" to only
    remove nodes with zero non-daemonset pods.
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
