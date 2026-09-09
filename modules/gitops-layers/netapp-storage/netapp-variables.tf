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
