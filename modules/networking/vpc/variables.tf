#------------------------------------------------------------------------------
# VPC Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster. Used for resource naming and tagging."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones for subnet creation."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets (one per AZ)."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (one per AZ). Only used when egress_type = 'nat'."
  default     = []
}

variable "egress_type" {
  type        = string
  description = <<-EOT
    Type of internet egress for the private subnets:
    - "nat": Creates public subnets, Internet Gateway, and NAT gateways (standalone deployment)
    - "tgw": No public infrastructure; egress via Transit Gateway (requires transit_gateway_id)
    - "proxy": No public infrastructure; egress via HTTP/HTTPS proxy configured in cluster
    - "none": No public infrastructure, no egress (zero-egress/air-gapped, HCP only)
  EOT
  default     = "nat"

  validation {
    condition     = contains(["nat", "tgw", "proxy", "none"], var.egress_type)
    error_message = "egress_type must be one of: nat, tgw, proxy, none"
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = <<-EOT
    Use a single NAT gateway instead of one per AZ.
    - true: Cost savings (~$32/month per NAT saved), single point of failure
    - false: High availability, one NAT per AZ survives AZ failure
  EOT
  default     = false
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit Gateway ID for egress routing. Required when egress_type = 'tgw'."
  default     = null
}

variable "transit_gateway_route_cidr" {
  type        = string
  description = "CIDR block to route via Transit Gateway (typically 0.0.0.0/0 for internet egress)."
  default     = "0.0.0.0/0"
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs. Logs are sent to CloudWatch and encrypted with KMS."
  default     = false
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Number of days to retain VPC flow logs in CloudWatch."
  default     = 30
}

variable "infrastructure_kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for infrastructure encryption (flow logs). Required if enable_flow_logs is true."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
