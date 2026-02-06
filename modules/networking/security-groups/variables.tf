#------------------------------------------------------------------------------
# Additional Security Groups Module - Variables
#
# This module creates or uses existing security groups for ROSA clusters.
# Supports both ROSA HCP (compute only) and ROSA Classic (compute, control plane, infra).
#------------------------------------------------------------------------------

variable "enabled" {
  type        = bool
  description = <<-EOT
    Enable additional security groups for the cluster.
    When false, no security groups are created and empty lists are returned.
  EOT
  default     = false
}

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster. Used for naming security groups."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC where security groups will be created."
}

variable "vpc_cidr" {
  type        = string
  description = <<-EOT
    CIDR block of the VPC. Used for the intra-VPC template rules.
    Required when use_intra_vpc_template = true.
  EOT
  default     = ""
}

#------------------------------------------------------------------------------
# Cluster Type Configuration
#------------------------------------------------------------------------------

variable "cluster_type" {
  type        = string
  description = <<-EOT
    Type of ROSA cluster:
    - "hcp": ROSA HCP (only compute security groups supported)
    - "classic": ROSA Classic (compute, control_plane, and infra security groups supported)
  EOT
  default     = "hcp"

  validation {
    condition     = contains(["hcp", "classic"], var.cluster_type)
    error_message = "cluster_type must be either 'hcp' or 'classic'."
  }
}

#------------------------------------------------------------------------------
# Existing Security Group IDs (Option A: Use existing)
#
# Provide existing security group IDs to attach to the cluster.
# These take precedence over created security groups if both are provided.
#------------------------------------------------------------------------------

variable "existing_compute_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of existing security group IDs to attach to compute/worker nodes.
    These are applied in addition to any security groups created by this module.
  EOT
  default     = []
}

variable "existing_control_plane_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    (Classic only) List of existing security group IDs to attach to control plane nodes.
    Ignored for HCP clusters.
  EOT
  default     = []
}

variable "existing_infra_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    (Classic only) List of existing security group IDs to attach to infrastructure nodes.
    Ignored for HCP clusters.
  EOT
  default     = []
}

#------------------------------------------------------------------------------
# Template Security Groups
#
# Quick-start templates for common use cases.
#------------------------------------------------------------------------------

variable "use_intra_vpc_template" {
  type        = bool
  description = <<-EOT
    Create a template security group allowing intra-VPC traffic.
    
    WARNING: This creates permissive rules allowing all traffic within the VPC CIDR.
    While convenient for development, consider more restrictive rules for production.
    
    The template creates rules allowing:
    - All TCP traffic from VPC CIDR
    - All UDP traffic from VPC CIDR
    - All ICMP traffic from VPC CIDR
    
    Requires vpc_cidr to be set.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Custom Security Group Rules (Option B: Create new)
#
# Define custom security group rules for each node type.
# Rules are applied to new security groups created by this module.
#------------------------------------------------------------------------------

variable "compute_ingress_rules" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = optional(list(string), [])
    # Allow referencing other security groups (for peered VPCs, etc.)
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  description = <<-EOT
    Custom ingress rules for compute/worker node security group.
    
    Example:
    compute_ingress_rules = [
      {
        description = "Allow HTTPS from on-prem"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["10.100.0.0/16"]
      }
    ]
  EOT
  default     = []
}

variable "compute_egress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  description = "Custom egress rules for compute/worker node security group."
  default     = []
}

variable "control_plane_ingress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  description = "(Classic only) Custom ingress rules for control plane node security group."
  default     = []
}

variable "control_plane_egress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  description = "(Classic only) Custom egress rules for control plane node security group."
  default     = []
}

variable "infra_ingress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  description = "(Classic only) Custom ingress rules for infrastructure node security group."
  default     = []
}

variable "infra_egress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  description = "(Classic only) Custom egress rules for infrastructure node security group."
  default     = []
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to created security groups."
  default     = {}
}
