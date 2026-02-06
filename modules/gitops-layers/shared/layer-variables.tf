#------------------------------------------------------------------------------
# GitOps Layer Variables - Shared Definitions
#
# This file contains variable definitions that should be copied or referenced
# by environment variable files. Keeping layer variables in sync across
# environments ensures consistent behavior.
#
# GITOPS-VAR-CHAIN: Shared variable definitions used by sub-modules.
# When adding a variable here, also update:
#   1. modules/gitops-layers/operator/variables.tf or resources/variables.tf
#   2. environments/*/variables.tf  (all 4 environments)
#   3. environments/*/main.tf       (passthrough in module blocks)
# Search "GITOPS-VAR-CHAIN" to find all touchpoints.
#
# See docs/GITOPS-LAYERS-GUIDE.md for how to add new layers.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Layer Enable Flags
#------------------------------------------------------------------------------

variable "enable_layer_terminal" {
  type        = bool
  description = "Enable Web Terminal layer (browser-based cluster access)."
  default     = false
}

variable "enable_layer_oadp" {
  type        = bool
  description = "Enable OADP layer (backup/restore with Velero)."
  default     = false
}

variable "enable_layer_virtualization" {
  type        = bool
  description = "Enable OpenShift Virtualization layer (KubeVirt for VMs)."
  default     = false
}

#------------------------------------------------------------------------------
# OADP Layer Configuration
#------------------------------------------------------------------------------

variable "oadp_backup_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain backups.
    Controls both Velero backup TTL and S3 lifecycle rules.
  EOT
  default     = 30
}

#------------------------------------------------------------------------------
# Virtualization Layer Configuration
#
# Machine pools for virtualization are defined via the standard machine_pools
# variable in tfvars. See examples/ocpvirtualization.tfvars.
# The operator module uses virt_node_selector and virt_tolerations for the
# HyperConverged CR.
#------------------------------------------------------------------------------
