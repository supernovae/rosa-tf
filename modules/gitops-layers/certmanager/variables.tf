#------------------------------------------------------------------------------
# Cert-Manager Resources Module Variables
#
# This module creates AWS resources for cert-manager DNS01 challenges:
# - IAM role with OIDC trust for cert-manager service account
# - Route53 permissions for DNS01 challenge resolution
# - Optional Route53 hosted zone creation
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    OIDC provider endpoint URL (without https:// prefix).
    Get from: module.iam_roles.oidc_endpoint_url
  EOT
}

variable "aws_region" {
  type        = string
  description = <<-EOT
    AWS region for resource creation.
    GovCloud: us-gov-west-1 or us-gov-east-1
    Commercial: us-east-1, us-west-2, etc.
  EOT
}

#------------------------------------------------------------------------------
# Route53 Configuration
#------------------------------------------------------------------------------

variable "hosted_zone_id" {
  type        = string
  description = <<-EOT
    ID of an existing Route53 hosted zone for DNS01 challenges.
    Required when create_hosted_zone = false.
    
    The IAM policy is scoped to this specific zone for least-privilege access.
    cert-manager will create/delete TXT records in this zone for ACME challenges.
  EOT
  default     = ""
}

variable "hosted_zone_domain" {
  type        = string
  description = <<-EOT
    Domain name for the Route53 hosted zone.
    Required when create_hosted_zone = true.
    Example: "apps.example.com" or "example.com"
  EOT
  default     = ""
}

variable "create_hosted_zone" {
  type        = bool
  description = <<-EOT
    Whether to create a new Route53 hosted zone for cert-manager.
    
    Set to true if you don't have an existing hosted zone.
    Set to false and provide hosted_zone_id to use an existing zone.
    
    IMPORTANT: If creating a new zone, you must configure your domain
    registrar to delegate DNS to the AWS nameservers. The nameservers
    are available in the module outputs.
  EOT
  default     = false
}

variable "enable_dnssec" {
  type        = bool
  description = <<-EOT
    Enable DNSSEC signing on the Route53 hosted zone.
    Only applies when create_hosted_zone = true.

    DNSSEC protects against DNS spoofing and cache poisoning by
    cryptographically signing DNS records. A customer-managed KMS key
    (ECC_NIST_P256) is created for the Key Signing Key (KSK).

    After enabling, you must add a DS record to the parent zone
    (your domain registrar) to complete the chain of trust.
    The DS record value is available in the outputs.

    For Commercial: KMS key is created in the deployment region
    (Route53 handles the us-east-1 requirement internally).
    For GovCloud: KMS key is created in the deployment region.
  EOT
  default     = true
}

variable "enable_query_logging" {
  type        = bool
  description = <<-EOT
    Enable DNS query logging to CloudWatch Logs for the Route53 hosted zone.
    Only applies when create_hosted_zone = true.

    Logs DNS queries for security monitoring and troubleshooting.

    IMPORTANT: For Commercial AWS, Route53 query logging requires the
    CloudWatch log group to be in us-east-1. This only works when the
    module is deployed in us-east-1. Set to false for other regions.
    For GovCloud, the log group is created in the deployment region.
  EOT
  default     = true
}

variable "query_log_retention_days" {
  type        = number
  description = "Number of days to retain Route53 query logs in CloudWatch. Minimum 365 for compliance."
  default     = 365
}

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting CloudWatch log groups. Null uses AWS default encryption."
  default     = null
}

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

variable "iam_role_path" {
  type        = string
  description = "Path for the IAM role."
  default     = "/"
}

#------------------------------------------------------------------------------
# Environment Detection
#------------------------------------------------------------------------------

variable "is_govcloud" {
  type        = bool
  description = <<-EOT
    Whether this is a GovCloud deployment.
    Affects partition used in IAM ARN construction.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
