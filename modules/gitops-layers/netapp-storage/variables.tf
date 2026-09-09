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



variable "fsx_admin_password" {
  type        = string
  description = "FSx filesystem administrator password. Separate from the SVM password. Sensitive marking does not encrypt Terraform state."
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
    
    SINGLE_AZ_1/2: Single-AZ; retain generation on existing file systems.
    MULTI_AZ_1/2: Multi-AZ failover. Gen2 availability must be confirmed per region.
  EOT
  default     = "SINGLE_AZ_1"

  validation {
    condition     = contains(["SINGLE_AZ_1", "MULTI_AZ_1", "SINGLE_AZ_2", "MULTI_AZ_2"], var.deployment_type)
    error_message = "Use SINGLE_AZ_1, MULTI_AZ_1, SINGLE_AZ_2 or MULTI_AZ_2; confirm regional availability."
  }
}

variable "storage_capacity_gb" {
  type        = number
  description = "Provisioned SSD capacity in GiB (1024–196608 for the supported one-HA-pair configuration). Billed for provisioned SSD, not only written bytes."
  default     = 1024

  validation {
    condition     = var.storage_capacity_gb >= 1024 && var.storage_capacity_gb <= 196608 && floor(var.storage_capacity_gb) == var.storage_capacity_gb
    error_message = "storage_capacity_gb must be an integer from 1024 through 196608 for one HA pair."
  }
}

variable "throughput_capacity_mbps" {
  type        = number
  description = "MBps for one HA pair. Gen1: 128/256/512/1024/2048/4096; Single-AZ2: 1536/3072/6144; Multi-AZ2: 384/768/1536/3072/6144."
  default     = 128

  validation {
    condition     = contains(var.deployment_type == "SINGLE_AZ_2" ? [1536, 3072, 6144] : var.deployment_type == "MULTI_AZ_2" ? [384, 768, 1536, 3072, 6144] : [128, 256, 512, 1024, 2048, 4096], var.throughput_capacity_mbps)
    error_message = "Use a throughput value supported by the selected generation; see docs/NETAPP-STORAGE.md."
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
    Must be within the VPC CIDR and not overlap existing subnets. Size for generation and endpoint count.
    Required when creating dedicated subnets; allocate explicit non-overlapping ranges.
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


#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
