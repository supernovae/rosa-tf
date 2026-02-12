#------------------------------------------------------------------------------
# GitOps Layer Resources Module - Variables
#
# This module consolidates all infrastructure required by GitOps layers.
# It creates S3 buckets, IAM roles, etc. based on which layers are enabled.
#
# GITOPS-VAR-CHAIN: This is the resources module's variable interface.
# When adding a variable here, also update:
#   1. environments/*/variables.tf  (all 4 environments)
#   2. environments/*/main.tf       (passthrough in module "gitops_resources" blocks)
# Search "GITOPS-VAR-CHAIN" to find all touchpoints.
#
# See docs/GITOPS-LAYERS-GUIDE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Inputs
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "cluster_type" {
  type        = string
  description = "Type of ROSA cluster: 'classic' or 'hcp'."
  default     = "classic"

  validation {
    condition     = contains(["classic", "hcp"], var.cluster_type)
    error_message = "cluster_type must be 'classic' or 'hcp'."
  }
}

variable "oidc_endpoint_url" {
  type        = string
  description = "OIDC endpoint URL for IAM role trust policies."
}

variable "aws_region" {
  type        = string
  description = "AWS region for resources."
  default     = null
}

#------------------------------------------------------------------------------
# Optional Inputs
#------------------------------------------------------------------------------

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting layer resources (S3, etc.). Null uses AWS default."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}

# NOTE: force_destroy_bucket has been removed
# S3 buckets (OADP backups, Loki logs) are NEVER automatically deleted
# to prevent accidental data loss. Users must manually empty and delete
# buckets after terraform destroy. See outputs for bucket names.

#------------------------------------------------------------------------------
# Layer Enable Flags
#------------------------------------------------------------------------------

variable "enable_layer_terminal" {
  type        = bool
  description = "Enable Web Terminal layer."
  default     = false
}

variable "enable_layer_oadp" {
  type        = bool
  description = "Enable OADP layer."
  default     = false
}

variable "enable_layer_virtualization" {
  type        = bool
  description = "Enable Virtualization layer."
  default     = false
}

variable "enable_layer_monitoring" {
  type        = bool
  description = "Enable Monitoring and Logging layer."
  default     = false
}

variable "enable_layer_certmanager" {
  type        = bool
  description = "Enable Cert-Manager layer for automated certificate lifecycle."
  default     = false
}

#------------------------------------------------------------------------------
# OADP Configuration
#------------------------------------------------------------------------------

variable "oadp_backup_retention_days" {
  type        = number
  description = "Days to retain OADP backups."
  default     = 30
}

#------------------------------------------------------------------------------
# Monitoring Configuration
#------------------------------------------------------------------------------

variable "monitoring_retention_days" {
  type        = number
  description = "Days to retain metrics and logs."
  default     = 30
}

variable "monitoring_prometheus_storage_size" {
  type        = string
  description = "Size of Prometheus PVC."
  default     = "100Gi"
}

variable "monitoring_storage_class" {
  type        = string
  description = "StorageClass for monitoring PVCs."
  default     = "gp3-csi"
}

variable "is_govcloud" {
  type        = bool
  description = "Whether this is a GovCloud deployment."
  default     = false
}

#------------------------------------------------------------------------------
# Cert-Manager Configuration
#------------------------------------------------------------------------------

variable "certmanager_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for DNS01 challenges. Required when not creating a new zone."
  default     = ""
}

variable "certmanager_hosted_zone_domain" {
  type        = string
  description = "Domain for the Route53 hosted zone. Required when creating a new zone."
  default     = ""
}

variable "certmanager_create_hosted_zone" {
  type        = bool
  description = "Whether to create a new Route53 hosted zone for cert-manager."
  default     = false
}

variable "certmanager_enable_dnssec" {
  type        = bool
  description = "Enable DNSSEC signing on the cert-manager Route53 hosted zone."
  default     = true
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version for API compatibility."
  default     = "4.20"
}
