#------------------------------------------------------------------------------
# ROSA Classic Machine Pools Variables
#------------------------------------------------------------------------------

variable "cluster_id" {
  type        = string
  description = "ID of the ROSA Classic cluster."
}

#------------------------------------------------------------------------------
# Machine Pools Configuration
#
# Generic list of machine pools. Each pool is fully configurable.
# Classic supports additional features: spot instances, disk size, multi-AZ.
# See docs/MACHINE-POOLS.md for examples of GPU, bare metal, ARM, spot, etc.
#
# Example:
#   machine_pools = [
#     {
#       name          = "gpu-spot"
#       instance_type = "g4dn.xlarge"
#       spot          = { enabled = true, max_price = "0.50" }
#       autoscaling   = { enabled = true, min = 0, max = 3 }
#       multi_az      = false
#       labels        = { "node-role.kubernetes.io/gpu" = "", "spot" = "true" }
#       taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
#     },
#     {
#       name          = "metal"
#       instance_type = "m6i.metal"
#       replicas      = 2
#       labels        = { "node-role.kubernetes.io/metal" = "" }
#     }
#   ]
#------------------------------------------------------------------------------

variable "machine_pools" {
  type = list(object({
    name          = string
    instance_type = string
    replicas      = optional(number, 2)

    # Autoscaling configuration (mutually exclusive with replicas when enabled)
    autoscaling = optional(object({
      enabled = bool
      min     = number
      max     = number
    }))

    # Spot instance configuration (Classic only - HCP coming soon)
    spot = optional(object({
      enabled   = bool
      max_price = optional(string) # Leave empty for on-demand price cap
    }))

    # Disk configuration
    disk_size = optional(number, 300) # GB

    # Node labels for workload targeting
    labels = optional(map(string), {})

    # Node taints for workload isolation
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string # NoSchedule, PreferNoSchedule, NoExecute
    })), [])

    # AZ configuration
    multi_az          = optional(bool, true)
    availability_zone = optional(string) # Only used if multi_az = false

    # Subnet placement (optional)
    subnet_id = optional(string)
  }))

  description = <<-EOT
    List of additional machine pools to create.
    
    Each pool object supports:
    - name: Pool name (required)
    - instance_type: EC2 instance type (required)
    - replicas: Fixed replica count (default: 2, ignored if autoscaling enabled)
    - autoscaling: { enabled = bool, min = number, max = number }
    - spot: { enabled = bool, max_price = string } (Classic only)
    - disk_size: Root disk size in GB (default: 300)
    - labels: Map of node labels for workload targeting
    - taints: List of taints for workload isolation
    - multi_az: Distribute across AZs (default: true)
    - availability_zone: Specific AZ (only if multi_az = false)
    - subnet_id: Override default subnet
    
    See docs/MACHINE-POOLS.md for detailed examples including:
    - GPU pools (NVIDIA)
    - GPU Spot pools (cost-effective ML/batch)
    - Bare metal pools (OpenShift Virtualization)
    - ARM/Graviton pools (cost optimization)
    - High memory pools
  EOT

  default = []
}

#------------------------------------------------------------------------------
# Common Configuration
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
