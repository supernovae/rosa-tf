#------------------------------------------------------------------------------
# ROSA HCP Account Layer - Variables
#
# Configure shared account-level resources for ROSA HCP.
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# AWS Configuration
#------------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS region for account resources."
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., 'account', 'shared')."
  default     = "account"
}

#------------------------------------------------------------------------------
# Red Hat OpenShift Cluster Manager
#------------------------------------------------------------------------------

variable "ocm_token" {
  type        = string
  description = <<-EOT
    OCM offline token for GovCloud authentication.
    Get from: https://console.openshiftusgov.com/openshift/token

    Set via environment variable:
      export TF_VAR_ocm_token="your-offline-token"

    Note: For commercial cloud, use rhcs_client_id and rhcs_client_secret
    instead (service account authentication).
  EOT
  sensitive   = true
  default     = null
}

variable "rhcs_client_id" {
  type        = string
  description = <<-EOT
    RHCS service account client ID for Commercial AWS authentication.
    Create at: https://console.redhat.com/iam/service-accounts

    Set via environment variable:
      export TF_VAR_rhcs_client_id="your-client-id"
  EOT
  sensitive   = false
  default     = null
}

variable "rhcs_client_secret" {
  type        = string
  description = <<-EOT
    RHCS service account client secret for Commercial AWS authentication.
    Generated when creating a service account.

    Set via environment variable:
      export TF_VAR_rhcs_client_secret="your-client-secret"
  EOT
  sensitive   = true
  default     = null
}

variable "target_partition" {
  type        = string
  description = <<-EOT
    Target AWS partition for validation.
    Set in tfvars to ensure correct configuration is used.
    
    Values:
      - "commercial" for AWS (aws partition)
      - "govcloud" for AWS GovCloud (aws-us-gov partition)
  EOT

  validation {
    condition     = contains(["commercial", "govcloud"], var.target_partition)
    error_message = "target_partition must be 'commercial' or 'govcloud'."
  }
}

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

variable "account_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for account IAM role names.
    
    Default is "ManagedOpenShift" to match ROSA CLI convention.
    This enables interoperability with roles created via:
      rosa create account-roles --hosted-cp --prefix ManagedOpenShift
    
    Role names will be:
      - {prefix}-HCP-ROSA-Installer-Role
      - {prefix}-HCP-ROSA-Support-Role
      - {prefix}-HCP-ROSA-Worker-Role
    
    IMPORTANT: Use the same prefix for all HCP clusters in this account.
  EOT
  default     = "ManagedOpenShift"
}

variable "path" {
  type        = string
  description = "IAM path for roles and policies."
  default     = "/"
}

variable "kms_key_arns" {
  type        = list(string)
  description = <<-EOT
    List of KMS key ARNs to grant access to installer and support roles.
    Required when using customer-managed KMS keys for cluster encryption.
    
    Leave empty if using AWS managed keys.
  EOT
  default     = []
}

#------------------------------------------------------------------------------
# Optional Features
#------------------------------------------------------------------------------

# variable "create_shared_kms" {
#   type        = bool
#   description = "Create shared KMS keys for all HCP clusters."
#   default     = false
# }

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
