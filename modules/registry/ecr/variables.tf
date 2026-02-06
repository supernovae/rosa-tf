#------------------------------------------------------------------------------
# ECR Module Variables
#------------------------------------------------------------------------------

# Note: create_ecr is controlled at the environment level via module count.
# This module assumes it should create resources when instantiated.

variable "prevent_destroy" {
  type        = bool
  description = <<-EOT
    Prevent ECR repository from being destroyed with the cluster.
    
    When true:
    - Repository survives terraform destroy of the cluster
    - Must explicitly set to false and run targeted destroy to remove
    - Useful for shared registries or preserving images across cluster rebuilds
    
    To destroy when prevent_destroy = true:
      1. Set prevent_destroy = false in tfvars
      2. Run: terraform destroy -target=module.ecr
  EOT
  default     = false
}

variable "repository_name" {
  type        = string
  description = <<-EOT
    Name of the ECR repository.
    If not provided, defaults to {cluster_name}-registry.
  EOT
  default     = ""
}

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster. Used for default repository naming."
}

variable "kms_key_arn" {
  type        = string
  description = <<-EOT
    ARN of the KMS key for ECR image encryption.
    If not provided, uses AES-256 encryption (AWS managed).
  EOT
  default     = null
}

variable "image_tag_mutability" {
  type        = string
  description = <<-EOT
    The tag mutability setting for the repository.
    - MUTABLE: Allow overwriting existing image tags
    - IMMUTABLE: Prevent overwriting existing image tags (recommended for production)
  EOT
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  type        = bool
  description = "Enable image scanning on push for vulnerability detection."
  default     = true
}

variable "lifecycle_policy_enabled" {
  type        = bool
  description = "Enable lifecycle policy to manage image retention."
  default     = true
}

variable "lifecycle_untagged_days" {
  type        = number
  description = "Number of days to retain untagged images before cleanup."
  default     = 14
}

variable "lifecycle_keep_count" {
  type        = number
  description = "Number of tagged images to retain (keeps most recent)."
  default     = 30
}

variable "force_delete" {
  type        = bool
  description = "Force delete repository even if it contains images."
  default     = false
}

variable "generate_idms" {
  type        = bool
  description = <<-EOT
    Generate an ImageDigestMirrorSet (IDMS) YAML file for zero-egress clusters.
    
    When true, creates outputs/idms-config.yaml which must be applied to the
    cluster before installing operators from a mirrored registry.
    
    See docs/ZERO-EGRESS.md for the complete workflow.
  EOT
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to ECR resources."
  default     = {}
}

#------------------------------------------------------------------------------
# VPC Endpoint Configuration
#------------------------------------------------------------------------------

variable "create_vpc_endpoints" {
  type        = bool
  description = <<-EOT
    Create VPC endpoints for ECR (ecr.api and ecr.dkr).

    Defaults to true because:
    1. Cost efficiency - Avoids NAT Gateway egress charges for image pulls
    2. Required for zero-egress - Clusters without internet need private ECR access
    3. Security - All ECR traffic stays within AWS private network

    The endpoints are Interface type and require:
    - vpc_id: The VPC where endpoints will be created
    - private_subnet_ids: Subnets for endpoint ENIs (should match worker subnets)
    
    NOTE: When true, vpc_id and private_subnet_ids must be provided.
  EOT
  default     = true
}

variable "vpc_id" {
  type        = string
  description = <<-EOT
    VPC ID where ECR endpoints will be created.
    Required when create_vpc_endpoints = true.
  EOT
  default     = null
}

variable "private_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    List of private subnet IDs for ECR endpoint ENIs.
    Should match the subnets where ROSA worker nodes run.
    Required when create_vpc_endpoints = true.
  EOT
  default     = []
}

variable "endpoint_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    Security group IDs for ECR VPC endpoints.
    If not provided, a security group allowing HTTPS (443) from the VPC CIDR is created.
  EOT
  default     = []
}

variable "vpc_cidr" {
  type        = string
  description = <<-EOT
    VPC CIDR block for the default endpoint security group.
    Only used when endpoint_security_group_ids is empty.
  EOT
  default     = null
}
