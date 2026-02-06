#------------------------------------------------------------------------------
# IAM Roles Module Variables - ROSA Classic
#
# ROSA Classic uses CLUSTER-SCOPED IAM roles:
# - Each cluster has its own set of account roles (Installer, Support, ControlPlane, Worker)
# - Roles are named using cluster_name as the default prefix
# - Destroying a cluster cleanly removes its IAM roles
# - No shared roles between clusters (unlike HCP which uses account-level roles)
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster. Used as default prefix for IAM role names."
}

variable "account_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for account IAM role names.
    Defaults to cluster_name for cluster-scoped roles.
    
    Role names will be: {prefix}-Installer-Role, {prefix}-Support-Role, etc.
    
    IMPORTANT: For ROSA Classic, each cluster should have its own roles.
    Using a shared prefix across clusters is not recommended.
  EOT
  default     = null # Will use cluster_name if not set
}

variable "operator_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for operator IAM role names.
    Defaults to cluster_name if not specified.
  EOT
  default     = null # Will use cluster_name if not set
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version for the cluster (e.g., 4.16.50)."
}

variable "path" {
  type        = string
  description = "IAM path for roles and policies."
  default     = "/"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}

variable "create_operator_roles" {
  type        = bool
  description = "If true, create and manage operator roles via Terraform. Set to false to manage operator roles externally via rosa CLI."
  default     = true
}

variable "attach_ecr_policy" {
  type        = bool
  description = <<-EOT
    Attach AmazonEC2ContainerRegistryReadOnly policy to worker role.
    Enables worker nodes to pull images from ECR repositories.
    Required when using ECR for container images.
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
    - installer_role_arn_for_oidc: ARN of installer role for OIDC creation
    
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
