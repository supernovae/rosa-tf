#------------------------------------------------------------------------------
# ROSA HCP Machine Pools Variables
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "cluster_id" {
  type        = string
  description = "ID of the ROSA HCP cluster."
}

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for machine pools.
    Must be within n-2 of the control plane version.
  EOT

  validation {
    condition     = can(regex("^4\\.[0-9]+\\.[0-9]+$", var.openshift_version)) || var.openshift_version == ""
    error_message = "OpenShift version must be in format X.Y.Z (e.g., 4.16.0)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Default subnet ID for machine pools."
}

variable "az_subnet_map" {
  type        = map(string)
  description = <<-EOT
    Map of availability zone name to private subnet ID.
    Enables pools to target a specific AZ using the availability_zone field
    (e.g., for GPU instances only available in certain AZs).
  EOT
  default     = {}
}

#------------------------------------------------------------------------------
# Machine Pools Configuration
#
# Generic list of machine pools. Each pool is fully configurable.
# See docs/MACHINE-POOLS.md for examples of GPU, bare metal, ARM, etc.
#
# Example:
#   machine_pools = [
#     {
#       name          = "gpu"
#       instance_type = "g4dn.xlarge"
#       replicas      = 1
#       labels        = { "node-role.kubernetes.io/gpu" = "" }
#       taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
#     },
#     {
#       name          = "graviton"
#       instance_type = "m6g.xlarge"
#       replicas      = 2
#       autoscaling   = { enabled = true, min = 1, max = 5 }
#       labels        = { "kubernetes.io/arch" = "arm64" }
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

    # Node labels for workload targeting
    labels = optional(map(string), {})

    # Node taints for workload isolation
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string # NoSchedule, PreferNoSchedule, NoExecute
    })), [])

    # AZ targeting (optional) - resolves to subnet via az_subnet_map
    # Use when an instance type is only available in specific AZs (e.g., g7e in us-east-1b)
    availability_zone = optional(string)

    # Override default subnet (optional, mutually exclusive with availability_zone)
    subnet_id = optional(string)

    # ECR policy attachment (optional)
    # When true, attaches AmazonEC2ContainerRegistryReadOnly policy to this pool's instance profile
    attach_ecr_policy = optional(bool, false)
  }))

  description = <<-EOT
    List of additional machine pools to create.
    
    Each pool object supports:
    - name: Pool name (required)
    - instance_type: EC2 instance type (required)
    - replicas: Fixed replica count (default: 2, ignored if autoscaling enabled)
    - autoscaling: { enabled = bool, min = number, max = number }
    - labels: Map of node labels for workload targeting
    - taints: List of taints for workload isolation
    - availability_zone: Target a specific AZ (requires az_subnet_map)
    - subnet_id: Override default subnet (alternative to availability_zone)
    - attach_ecr_policy: Attach ECR readonly policy to pool's instance profile (default: false)
    
    See docs/MACHINE-POOLS.md for detailed examples including:
    - GPU pools (NVIDIA) with AZ targeting
    - Bare metal pools (OpenShift Virtualization)
    - ARM/Graviton pools (cost optimization)
    - High memory pools
  EOT

  default = []
}

#------------------------------------------------------------------------------
# Common Configuration
#------------------------------------------------------------------------------

variable "auto_repair" {
  type        = bool
  description = "Enable auto-repair for machine pools."
  default     = true
}

variable "skip_version_validation" {
  type        = bool
  description = "Skip OpenShift version validation for machine pools."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
