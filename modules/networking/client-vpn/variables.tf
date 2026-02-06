#------------------------------------------------------------------------------
# Client VPN Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster (used for resource naming)."
}

variable "cluster_domain" {
  type        = string
  description = "Domain of the ROSA cluster (e.g., cluster-name.xxxx.p1.openshiftapps.com)."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC to attach the Client VPN endpoint to."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC (for authorization rules)."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs to associate with the VPN endpoint. At least one required."
}

variable "client_cidr_block" {
  type        = string
  description = <<-EOT
    CIDR block for VPN client IP addresses. Must not overlap with VPC CIDR.
    Minimum /22 (1024 addresses). AWS reserves half for HA.
    Example: "10.100.0.0/22"
  EOT
  default     = "10.100.0.0/22"
}

variable "dns_servers" {
  type        = list(string)
  description = <<-EOT
    DNS servers for VPN clients. If null, uses VPC default DNS.
    For cluster DNS resolution, use the VPC DNS server (VPC CIDR base + 2).
    Example: ["10.0.0.2"] for a 10.0.0.0/16 VPC.
  EOT
  default     = null
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service CIDR for authorization (optional)."
  default     = null
}

variable "split_tunnel" {
  type        = bool
  description = <<-EOT
    Enable split tunnel mode. When true, only VPC-destined traffic goes through VPN.
    When false, all traffic routes through VPN.
    Recommended: true (better performance, lower bandwidth costs).
  EOT
  default     = true
}

variable "session_timeout_hours" {
  type        = number
  description = "VPN session timeout in hours (8-24)."
  default     = 12

  validation {
    condition     = var.session_timeout_hours >= 8 && var.session_timeout_hours <= 24
    error_message = "Session timeout must be between 8 and 24 hours."
  }
}

variable "certificate_validity_days" {
  type        = number
  description = "Validity period for generated certificates in days."
  default     = 365
}

variable "certificate_organization" {
  type        = string
  description = "Organization name for certificate subject."
  default     = "ROSA GovCloud"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting VPN connection logs."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
