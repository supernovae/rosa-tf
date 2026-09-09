# Shared by all four roots, the operator module and provider-free tests.
variable "netapp_operator_config" {
  type = object({
    source                = optional(string, "certified-operators")
    source_namespace      = optional(string, "openshift-marketplace")
    install_plan_approval = optional(string, "Manual")
    image_registry        = optional(string, "")
    image_pull_secrets    = optional(list(string), [])
    node_prep_iscsi       = optional(bool, false)
    nodes_prepared        = optional(bool, false)
    enable_concurrency    = optional(bool, false)
    enable_force_detach   = optional(bool, false)
  })
  default     = {}
  description = "Certified Trident installation. Manual approval protects storage upgrades; node preparation can roll workers and must be explicitly approved."
  validation {
    condition     = contains(["Manual", "Automatic"], var.netapp_operator_config.install_plan_approval)
    error_message = "Trident InstallPlan approval must be Manual or Automatic."
  }
}
variable "netapp_storage_config" {
  type = object({
    san_enabled          = optional(bool, true)
    use_chap             = optional(bool, true)
    backend_secret_name  = optional(string, "")
    management_endpoint  = optional(string, "")
    trusted_ca_pem       = optional(string, "")
    nas_unix_permissions = optional(string, "0770")
    qos_policy           = optional(string, "")
    nfs_nconnect         = optional(number, 1)
  })
  default     = {}
  description = "Verified ONTAP REST backends and retained storage classes. Supply trusted CA PEM and a separately managed Secret; CHAP requires all four CHAP keys."
  validation {
    condition     = can(regex("^0[0-7]{3}$", var.netapp_storage_config.nas_unix_permissions)) && contains([1, 2, 4, 8, 16], var.netapp_storage_config.nfs_nconnect)
    error_message = "Use octal NAS permissions and a tested nconnect value of 1, 2, 4, 8 or 16."
  }
  validation {
    condition     = var.netapp_storage_config.backend_secret_name == "" || can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.netapp_storage_config.backend_secret_name))
    error_message = "Backend Secret name must be a Kubernetes DNS name."
  }
}
# Shared by roots, resource aggregator and FSx module.
variable "fsx_svm_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Separate SVM vsadmin password for FSx creation/rotation; required when storage is enabled. Keep it in a secret-managed runner environment."
}
variable "netapp_fsx_config" {
  type = object({
    client_cidrs                    = optional(list(string), [])
    client_route_table_ids          = optional(list(string), [])
    automatic_backup_retention_days = optional(number, 7)
    daily_backup_start_time         = optional(string, "05:00")
    weekly_maintenance_start_time   = optional(string, "7:06:00")
    provisioned_iops                = optional(number, null)
  })
  default     = {}
  description = "FSx network, backup and performance settings. Empty client CIDRs use worker subnet CIDRs; BYO-VPC Multi-AZ needs explicit client route tables."
  validation {
    condition     = alltrue([for cidr in var.netapp_fsx_config.client_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 16, false)])
    error_message = "Supply bounded IPv4 client CIDRs (/16 or narrower); never all-address ranges."
  }
  validation {
    condition     = var.netapp_fsx_config.automatic_backup_retention_days >= 1 && var.netapp_fsx_config.automatic_backup_retention_days <= 90 && floor(var.netapp_fsx_config.automatic_backup_retention_days) == var.netapp_fsx_config.automatic_backup_retention_days
    error_message = "Retain daily FSx backups for an integer number of days from 1 through 90."
  }
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.netapp_fsx_config.daily_backup_start_time)) && can(regex("^[1-7]:([01][0-9]|2[0-3]):[0-5][0-9]$", var.netapp_fsx_config.weekly_maintenance_start_time))
    error_message = "Use UTC HH:MM for backups and d:HH:MM for maintenance."
  }
}
