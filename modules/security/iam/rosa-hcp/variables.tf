#------------------------------------------------------------------------------
# ROSA HCP IAM Module Variables
#
# ROSA HCP uses a layered IAM architecture:
#   - Account Roles (shared): Created once per account, shared by all HCP clusters
#   - Operator Roles (per-cluster): Created per cluster, tied to OIDC
#   - OIDC Config (per-cluster): Created per cluster
#
# Account roles can be:
#   1. Created by this module (create_account_roles = true, default for single cluster)
#   2. Auto-discovered from account layer (create_account_roles = false)
#   3. Explicitly provided via ARN variables (override discovery)
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster (used for tagging and operator roles)."
}

#------------------------------------------------------------------------------
# Account Role Configuration
#
# Account roles are SHARED across HCP clusters in an account.
# For multi-cluster deployments, deploy account roles via environments/account-hcp
# and set create_account_roles = false to discover them.
#------------------------------------------------------------------------------

variable "create_account_roles" {
  type        = bool
  description = <<-EOT
    Create account IAM roles.
    
    - false (default): Use existing shared account roles (recommended)
    - true: Create account roles (only use for environments/account-hcp)
    
    HCP account roles are shared across all clusters in an AWS account.
    They should be created once via environments/account-hcp or ROSA CLI,
    then reused by all HCP cluster deployments.
    
    When false, roles are auto-discovered by account_role_prefix, or you can
    provide explicit ARNs via installer_role_arn, support_role_arn, worker_role_arn.
  EOT
  default     = false
}

variable "account_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for account IAM roles.
    
    Default is "ManagedOpenShift" to match ROSA CLI convention.
    This enables interoperability with roles created via:
      rosa create account-roles --hosted-cp --prefix ManagedOpenShift
    
    Role names: {prefix}-HCP-ROSA-{Installer|Support|Worker}-Role
    
    Used for both role creation (create_account_roles = true) and 
    role discovery (create_account_roles = false).
  EOT
  default     = "ManagedOpenShift"
}

variable "installer_role_arn" {
  type        = string
  description = <<-EOT
    Explicit installer role ARN.
    When provided, overrides auto-discovery.
    Only used when create_account_roles = false.
  EOT
  default     = null
}

variable "support_role_arn" {
  type        = string
  description = <<-EOT
    Explicit support role ARN.
    When provided, overrides auto-discovery.
    Only used when create_account_roles = false.
  EOT
  default     = null
}

variable "worker_role_arn" {
  type        = string
  description = <<-EOT
    Explicit worker role ARN.
    When provided, overrides auto-discovery.
    Only used when create_account_roles = false.
  EOT
  default     = null
}

variable "operator_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for operator IAM roles (per-cluster).
    Defaults to cluster_name if not set.
    
    Roles will be named: {prefix}-{namespace}-{operator_name}
  EOT
  default     = null
}

variable "path" {
  type        = string
  description = "IAM path for roles."
  default     = "/"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to IAM resources."
  default     = {}
}

#------------------------------------------------------------------------------
# Deprecated Variables (kept for backwards compatibility)
#
# These variables are no longer used but kept to avoid breaking existing configs.
# See the architecture notes in main.tf for details on the new approach.
#------------------------------------------------------------------------------

variable "kms_key_arns" {
  type        = list(string)
  description = <<-EOT
    DEPRECATED - Not used in HCP.
    
    For ROSA HCP, KMS access is handled via KMS key policy (on the key itself),
    not IAM role policies. When you pass kms_key_arn to the cluster, RHCS manages
    the integration. Your KMS key policy must grant access to the operator roles.
    
    See modules/security/kms for proper KMS key policy configuration.
  EOT
  default     = []
}

variable "enable_kms_permissions" {
  type        = bool
  description = <<-EOT
    DEPRECATED - Not used in HCP.
    
    For ROSA HCP, KMS access is handled via KMS key policy, not IAM role policies.
    See kms_key_arns variable documentation for details.
  EOT
  default     = false
}

variable "attach_ecr_policy" {
  type        = bool
  description = <<-EOT
    DEPRECATED - Not used at account role level.
    
    For ROSA HCP, ECR access should be configured per-machine-pool using the
    computed instance_profile from rhcs_hcp_machine_pool.aws_node_pool.instance_profile.
    
    This allows granular control over which machine pools can pull from ECR,
    rather than applying to all clusters using shared account roles.
    
    See modules/cluster/machine-pools-hcp for per-pool ECR configuration.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# OIDC Configuration Options
#
# Three modes are supported:
# 1. Managed (default): Red Hat hosts OIDC, created per-cluster
# 2. Managed (shared): Use pre-created managed OIDC config
# 3. Unmanaged: Customer hosts OIDC in their AWS account
#
# See docs/OIDC.md for detailed documentation.
#------------------------------------------------------------------------------

variable "create_oidc_config" {
  type        = bool
  description = <<-EOT
    Create a new OIDC configuration.
    
    - true (default): Create a new OIDC config (managed or unmanaged based on managed_oidc)
    - false: Use an existing OIDC config (requires oidc_config_id and oidc_endpoint_url)
    
    Set to false when sharing OIDC config across clusters or using pre-created config.
  EOT
  default     = true
}

variable "oidc_config_id" {
  type        = string
  description = <<-EOT
    Existing OIDC configuration ID.
    Required when create_oidc_config = false.
    
    Obtain from:
    - Previous Terraform apply output
    - rosa list oidc-config
    - OpenShift Cluster Manager
  EOT
  default     = null

  validation {
    condition     = var.oidc_config_id == null || can(regex("^[a-z0-9]{32}$", var.oidc_config_id))
    error_message = "OIDC config ID must be a 32-character alphanumeric string."
  }
}

variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    Existing OIDC endpoint URL (without https://).
    Required when create_oidc_config = false.
    
    Example: rh-oidc.s3.us-east-1.amazonaws.com/abcd1234...
  EOT
  default     = null
}

variable "managed_oidc" {
  type        = bool
  description = <<-EOT
    Use Red Hat managed OIDC configuration.
    Only applies when create_oidc_config = true.
    
    - true (default): Red Hat hosts OIDC provider and manages private key
    - false: Customer hosts OIDC in their AWS account (unmanaged)
    
    Unmanaged OIDC requires:
    - oidc_private_key_secret_arn: Secrets Manager secret with private key
    - installer_role_arn: ARN of installer role for OIDC creation
    
    See docs/OIDC.md for unmanaged OIDC setup instructions.
  EOT
  default     = true
}

variable "oidc_private_key_secret_arn" {
  type        = string
  description = <<-EOT
    ARN of AWS Secrets Manager secret containing the OIDC private key.
    Required when create_oidc_config = true and managed_oidc = false.
    
    The secret must contain the RSA private key in PEM format.
    Create using: rosa create oidc-config --managed=false --mode=manual
    
    See docs/OIDC.md for setup instructions.
  EOT
  default     = null
}

variable "installer_role_arn_for_oidc" {
  type        = string
  description = <<-EOT
    ARN of installer role for unmanaged OIDC creation.
    Required when create_oidc_config = true and managed_oidc = false.
    
    This creates a chicken-and-egg situation since installer role needs OIDC.
    For unmanaged OIDC, create the role first using rosa CLI, then reference it.
  EOT
  default     = null
}
