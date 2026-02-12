#------------------------------------------------------------------------------
# BYO-VPC Subnet Helper Variables
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required
#------------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = <<-EOT
    ID of the existing VPC to create subnets in.
    Get this from the first cluster's output: terraform output vpc_id
  EOT
}

variable "cluster_name" {
  type        = string
  description = <<-EOT
    Name of the ROSA cluster these subnets are for.
    Used for resource naming and tagging (e.g., "my-cluster-2").
  EOT
}

variable "aws_region" {
  type        = string
  description = "AWS region where the VPC lives."
}

variable "availability_zones" {
  type        = list(string)
  description = <<-EOT
    Availability zones for subnet creation.
    Must match the AZs used by the parent VPC's subnets.

    Single-AZ example: ["us-east-1a"]
    Multi-AZ example:  ["us-east-1a", "us-east-1b", "us-east-1c"]
  EOT

  validation {
    condition     = contains([1, 3], length(var.availability_zones))
    error_message = "Provide 1 AZ (single-AZ) or 3 AZs (multi-AZ) to match ROSA topology."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDR blocks for the new private subnets (one per AZ).
    These must NOT overlap with any existing subnets in the VPC.

    Example for a /16 VPC where first cluster uses 10.0.0.0/20 - 10.0.32.0/20:
      Single-AZ: ["10.0.48.0/20"]
      Multi-AZ:  ["10.0.48.0/20", "10.0.64.0/20", "10.0.80.0/20"]
  EOT

  validation {
    condition     = length(var.private_subnet_cidrs) >= 1
    error_message = "At least one private subnet CIDR is required."
  }
}

#------------------------------------------------------------------------------
# Optional -- Public Subnets
#------------------------------------------------------------------------------

variable "create_public_subnets" {
  type        = bool
  description = "Create public subnets for the second cluster (needed for public ROSA clusters)."
  default     = false
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDR blocks for new public subnets (one per AZ).
    Only used when create_public_subnets = true.
    Must not overlap with any existing subnets in the VPC.
  EOT
  default     = []
}

#------------------------------------------------------------------------------
# Optional -- Egress Configuration
#------------------------------------------------------------------------------

variable "egress_type" {
  type        = string
  description = <<-EOT
    How the new subnets reach the internet:
    - "nat": Reuse the parent VPC's existing NAT gateway (default, zero extra cost)
    - "tgw": Route via Transit Gateway (for GovCloud / hub-spoke topologies)
  EOT
  default     = "nat"

  validation {
    condition     = contains(["nat", "tgw"], var.egress_type)
    error_message = "egress_type must be \"nat\" or \"tgw\"."
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit Gateway ID. Required when egress_type = \"tgw\"."
  default     = null
}

variable "transit_gateway_route_cidr" {
  type        = string
  description = "CIDR block to route via Transit Gateway (typically 0.0.0.0/0)."
  default     = "0.0.0.0/0"
}

#------------------------------------------------------------------------------
# Optional -- Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all created resources."
  default     = {}
}
