# Shared by all four roots, the operator module and provider-free tests.
variable "fsx_svm_nfs_endpoint" {
  type        = string
  default     = ""
  description = "SVM NFS data endpoint, distinct from the management LIF."
}
variable "netapp_client_cidrs" {
  type        = list(string)
  default     = []
  description = "Approved worker IPv4 CIDRs for Trident automatic export filtering."
}
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
    san_enabled            = optional(bool, true)
    use_chap               = optional(bool, true)
    backend_secret_name    = optional(string, "")
    management_endpoint    = optional(string, "")
    trusted_ca_pem         = optional(string, "")
    nas_unix_permissions   = optional(string, "0770")
    qos_policy             = optional(string, "")
    nfs_nconnect           = optional(number, 1)
    legacy_classes_enabled = optional(bool, false)
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
