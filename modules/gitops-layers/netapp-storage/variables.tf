#------------------------------------------------------------------------------
# NetApp Storage (FSx ONTAP) Resources Module - Variables
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Inputs
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where FSx ONTAP will be deployed."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC. Used for security group rules."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from the ROSA VPC. Used when create_dedicated_subnets = false."
}

variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    OIDC provider endpoint URL (without https:// prefix).
    Used for Trident CSI controller IRSA trust policy.
  EOT
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID for IAM role ARN construction."
}

variable "fsx_admin_password" {
  type        = string
  description = <<-EOT
    Password for the FSx ONTAP fsxadmin user and SVM vsadmin user.
    Must be 8-50 characters with at least one letter and one digit.
    
    This value is marked sensitive and stored only in encrypted Terraform state.
    For production, consider using External Secrets Operator to source from
    AWS Secrets Manager instead of passing as a Terraform variable.
  EOT
  sensitive   = true

  validation {
    condition     = can(regex("^.{8,50}$", var.fsx_admin_password))
    error_message = "FSx admin password must be 8-50 characters."
  }
}

#------------------------------------------------------------------------------
# FSx ONTAP Configuration
#------------------------------------------------------------------------------

variable "deployment_type" {
  type        = string
  description = <<-EOT
    FSx ONTAP deployment type.
    
    SINGLE_AZ_1: Single-AZ, lower cost, suitable for dev/test.
    MULTI_AZ_1:  Multi-AZ with automatic failover, recommended for production.
  EOT
  default     = "SINGLE_AZ_1"

  validation {
    condition     = contains(["SINGLE_AZ_1", "MULTI_AZ_1"], var.deployment_type)
    error_message = "deployment_type must be 'SINGLE_AZ_1' or 'MULTI_AZ_1'."
  }
}

variable "storage_capacity_gb" {
  type        = number
  description = <<-EOT
    Total SSD storage capacity in GiB. Minimum 1024 GiB.
    FSx ONTAP uses thin provisioning, so you only pay for data written.
  EOT
  default     = 1024

  validation {
    condition     = var.storage_capacity_gb >= 1024
    error_message = "storage_capacity_gb must be at least 1024."
  }
}

variable "throughput_capacity_mbps" {
  type        = number
  description = <<-EOT
    Sustained throughput capacity in MBps.
    Single-AZ: 128, 256, 512, 1024, 2048, 4096
    Multi-AZ:  128, 256, 512, 1024, 2048, 4096
  EOT
  default     = 128

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096], var.throughput_capacity_mbps)
    error_message = "throughput_capacity_mbps must be one of: 128, 256, 512, 1024, 2048, 4096."
  }
}

#------------------------------------------------------------------------------
# Networking
#------------------------------------------------------------------------------

variable "create_dedicated_subnets" {
  type        = bool
  description = <<-EOT
    Create dedicated /28 subnets for FSx ONTAP endpoints.
    
    false (default): Reuse ROSA private subnets. Simpler setup for dev.
    true: Create isolated subnets for FSxN endpoints. Recommended for production
          to separate storage traffic from compute traffic.
  EOT
  default     = false
}

variable "dedicated_subnet_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDR blocks for dedicated FSxN subnets. Only used when create_dedicated_subnets = true.
    Must be within the VPC CIDR. Minimum /28 per subnet.
    If empty, auto-calculated from VPC CIDR (last /28 blocks in the VPC range).
  EOT
  default     = []
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for FSxN subnets. Must match the ROSA cluster AZs."
  default     = []
}

variable "private_route_table_ids" {
  type        = list(string)
  description = "Route table IDs for dedicated subnet association. Required when create_dedicated_subnets = true."
  default     = []
}

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for FSx ONTAP encryption at rest. If null, uses AWS managed key."
  default     = null
}

#------------------------------------------------------------------------------
# IAM
#------------------------------------------------------------------------------

variable "iam_role_path" {
  type        = string
  description = "Path for IAM roles."
  default     = "/"
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
