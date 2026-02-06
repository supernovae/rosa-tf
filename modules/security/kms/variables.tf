#------------------------------------------------------------------------------
# KMS Module Variables
#
# Two separate KMS keys with independent mode selection:
#
# 1. CLUSTER KMS - For ROSA-managed resources only
#    - Worker node EBS volumes
#    - etcd encryption
#    - Policy follows Red Hat's expected permissions
#
# 2. INFRASTRUCTURE KMS - For non-ROSA resources
#    - Jump host EBS
#    - CloudWatch logs
#    - S3 buckets (OADP, etc.)
#    - VPN logs
#    - Strict separation from ROSA workloads
#
# Three modes for each key:
#
# 1. "provider_managed" (DEFAULT for Commercial)
#    - Uses AWS managed aws/ebs key
#    - No KMS keys created by Terraform
#    - Encryption at rest enabled via AWS default
#    - Best for: Development, cost-sensitive deployments
#    - NOT available in GovCloud (see note below)
#
# 2. "create" (DEFAULT for GovCloud)
#    - Terraform creates customer-managed KMS keys with aliases
#    - Full control over key policies and rotation
#    - Best for: Production, compliance requirements
#
# 3. "existing" (Bring your own key)
#    - User provides existing KMS key ARN(s)
#    - Terraform configures resources to use provided keys
#    - Best for: Centralized key management, shared keys
#
# GovCloud Note:
#   FedRAMP requires customer control over cryptographic keys (SC-12/SC-13).
#   While "provider_managed" is blocked at the environment level, advanced
#   users can use "existing" mode with the AWS managed key ARN for dev/staging
#   at their own risk. This is not recommended for production.
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster. Used for naming KMS keys and aliases."
}

#------------------------------------------------------------------------------
# Cluster KMS Configuration
# For ROSA-managed resources: worker EBS, etcd encryption
#------------------------------------------------------------------------------

variable "cluster_kms_mode" {
  type        = string
  description = <<-EOT
    Cluster KMS key management mode:
    - "provider_managed": Use AWS managed aws/ebs key (DEFAULT for Commercial)
    - "create": Terraform creates customer-managed KMS key (DEFAULT for GovCloud)
    - "existing": Use existing KMS key ARN (set cluster_kms_key_arn)
    
    This key is used ONLY for ROSA-managed resources (workers, etcd).
    Policy follows Red Hat's expected permissions for ROSA.
  EOT
  default     = "provider_managed"

  validation {
    condition     = contains(["provider_managed", "create", "existing"], var.cluster_kms_mode)
    error_message = "cluster_kms_mode must be one of: provider_managed, create, existing"
  }
}

variable "cluster_kms_key_arn" {
  type        = string
  description = <<-EOT
    ARN of existing KMS key for cluster encryption.
    Required when cluster_kms_mode = "existing".
    
    Key policy must grant access to ROSA account and operator roles.
    See Red Hat documentation for required permissions.
  EOT
  default     = null

  validation {
    condition     = var.cluster_kms_key_arn == null || can(regex("^arn:aws(-us-gov)?:kms:", var.cluster_kms_key_arn))
    error_message = "cluster_kms_key_arn must be a valid KMS key ARN."
  }
}

#------------------------------------------------------------------------------
# Infrastructure KMS Configuration
# For non-ROSA resources: jump host, CloudWatch, S3, VPN logs
#------------------------------------------------------------------------------

variable "infra_kms_mode" {
  type        = string
  description = <<-EOT
    Infrastructure KMS key management mode:
    - "provider_managed": Use AWS managed aws/ebs key (DEFAULT for Commercial)
    - "create": Terraform creates customer-managed KMS key (DEFAULT for GovCloud)
    - "existing": Use existing KMS key ARN (set infra_kms_key_arn)
    
    This key is used ONLY for non-ROSA resources:
    - Jump host EBS volumes
    - CloudWatch log encryption
    - S3 bucket encryption (OADP, backups)
    - VPN connection logs
    
    IMPORTANT: This key is NOT used for ROSA workers. Strict separation
    ensures blast radius containment between cluster and infrastructure.
  EOT
  default     = "provider_managed"

  validation {
    condition     = contains(["provider_managed", "create", "existing"], var.infra_kms_mode)
    error_message = "infra_kms_mode must be one of: provider_managed, create, existing"
  }
}

variable "infra_kms_key_arn" {
  type        = string
  description = <<-EOT
    ARN of existing KMS key for infrastructure encryption.
    Required when infra_kms_mode = "existing".
    
    Key policy must grant access to AWS services:
    - logs.{region}.amazonaws.com (CloudWatch)
    - s3.amazonaws.com (S3 buckets)
  EOT
  default     = null

  validation {
    condition     = var.infra_kms_key_arn == null || can(regex("^arn:aws(-us-gov)?:kms:", var.infra_kms_key_arn))
    error_message = "infra_kms_key_arn must be a valid KMS key ARN."
  }
}

#------------------------------------------------------------------------------
# Role Prefixes (required for cluster key "create" mode)
#------------------------------------------------------------------------------

variable "account_role_prefix" {
  type        = string
  description = "Prefix used for ROSA account roles. Required for cluster KMS key policy."
  default     = ""
}

variable "operator_role_prefix" {
  type        = string
  description = "Prefix used for ROSA operator roles. Required for cluster KMS key policy."
  default     = ""
}

#------------------------------------------------------------------------------
# HCP-specific Settings (only relevant for cluster key "create" mode)
#------------------------------------------------------------------------------

variable "is_hcp_cluster" {
  type        = bool
  description = <<-EOT
    Whether this is for an HCP cluster.
    When true and cluster_kms_mode = "create", adds permissions for:
    - EC2 and Auto Scaling service principals (for worker EBS encryption)
    - HCP operator roles (CAPA controller for node pool management)
    
    Does NOT affect infrastructure KMS key policy.
  EOT
  default     = false
}

variable "enable_hcp_etcd_encryption" {
  type        = bool
  description = <<-EOT
    Enable HCP-specific KMS policy statements for etcd encryption.
    Only applies when cluster_kms_mode = "create" and is_hcp_cluster = true.
    
    When true, adds permissions for HCP operator roles:
    - kube-system-kube-controller-manager (kms:DescribeKey)
    - kube-system-kms-provider (kms:Encrypt, kms:Decrypt, kms:DescribeKey)
    
    Does NOT affect infrastructure KMS key policy.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Key Settings (only relevant for "create" mode)
#------------------------------------------------------------------------------

variable "kms_key_deletion_window" {
  type        = number
  description = "Number of days before KMS keys are deleted after destruction. Must be between 7 and 30."
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to KMS keys."
  default     = {}
}
