variable "enable_layer_efs_storage" {
  type        = bool
  description = "Enable the supported Red Hat EFS CSI operator and retained shared-files storage."
  default     = false
}
variable "efs_performance_mode" {
  type        = string
  description = "EFS performance mode. This layer requires generalPurpose."
  default     = "generalPurpose"
}
variable "efs_throughput_mode" {
  type        = string
  description = "EFS throughput mode: elastic (default) or bursting."
  default     = "elastic"
}
variable "efs_encrypted" {
  type        = bool
  description = "EFS encryption must remain enabled."
  default     = true
}
variable "efs_storage_class_name" {
  type        = string
  description = "Retained EFS StorageClass; use a new name when migrating an immutable legacy class."
  default     = "efs-rwx-retain"
}

variable "efs_config" {
  description = "EFS operator lifecycle and approved worker NFS access. See docs/EFS-STORAGE.md."
  type = object({
    install_plan_approval      = optional(string, "Manual")
    catalog_source             = optional(string, "redhat-operators")
    catalog_namespace          = optional(string, "openshift-marketplace")
    manage_operator_group      = optional(bool, true)
    allowed_security_group_ids = optional(list(string), [])
  })
  default = {}
  validation {
    condition     = contains(["Manual", "Automatic"], var.efs_config.install_plan_approval)
    error_message = "EFS approval must be Manual or Automatic."
  }
  validation {
    condition     = length(trimspace(var.efs_config.catalog_source)) > 0 && length(trimspace(var.efs_config.catalog_namespace)) > 0
    error_message = "EFS needs a nonempty approved catalog source and namespace."
  }
  validation {
    condition     = alltrue([for id in var.efs_config.allowed_security_group_ids : can(regex("^sg-[a-f0-9]+$", id))]) && length(distinct(var.efs_config.allowed_security_group_ids)) == length(var.efs_config.allowed_security_group_ids)
    error_message = "Supply unique valid worker security group IDs."
  }
}
