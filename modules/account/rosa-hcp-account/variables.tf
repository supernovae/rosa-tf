#------------------------------------------------------------------------------
# ROSA HCP Account Roles Module - Variables
#
# These variables configure the shared account-level IAM roles for ROSA HCP.
# See docs/IAM-LIFECYCLE.md for architecture details.
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
    
    IMPORTANT: Use the same prefix across all HCP clusters in this account.
  EOT
  default     = "ManagedOpenShift"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]{0,19}$", var.account_role_prefix))
    error_message = "account_role_prefix must start with a letter, contain only alphanumeric characters, hyphens, or underscores, and be at most 20 characters (to avoid IAM role name length limits)."
  }
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
    
    Example:
      kms_key_arns = ["arn:aws:kms:us-east-1:123456789:key/12345678-1234-1234-1234-123456789"]
  EOT
  default     = []
}

variable "enable_kms_permissions" {
  type        = bool
  description = <<-EOT
    Enable KMS permissions for installer/support roles.
    Set to true when providing kms_key_arns.
    
    If not set, defaults to true when kms_key_arns is non-empty.
  EOT
  default     = null # Will be computed from kms_key_arns length if not set
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
