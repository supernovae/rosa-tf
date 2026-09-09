#------------------------------------------------------------------------------
# AWS EFS Storage Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where mount targets will be created."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for EFS mount targets (one per AZ)."
}

variable "oidc_endpoint_url" {
  type        = string
  description = "OIDC endpoint URL (without https://) for IRSA trust policy."
}

variable "efs_performance_mode" {
  type        = string
  description = "EFS performance mode; this layer requires generalPurpose."
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  type        = string
  description = "EFS throughput mode: elastic (default) or bursting."
  default     = "elastic"
}

variable "efs_encrypted" {
  type        = bool
  description = "EFS encryption at rest must remain enabled."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key ARN for EFS encryption. Empty uses AWS-managed key."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
