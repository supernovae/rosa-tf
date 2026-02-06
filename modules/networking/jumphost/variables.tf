#------------------------------------------------------------------------------
# Jump Host Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC."
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnet for the jump host (should be a private subnet)."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the jump host."
  default     = "t3.micro"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for the jump host. If null, uses latest Amazon Linux 2023."
  default     = null
}

variable "root_volume_size" {
  type        = number
  description = "Size of the root EBS volume in GB. Must be >= the AMI snapshot size (typically 30GB for Amazon Linux 2023)."
  default     = 30
}

variable "cluster_api_url" {
  type        = string
  description = "URL of the cluster API server."
}

variable "cluster_console_url" {
  type        = string
  description = "URL of the cluster web console."
}

variable "cluster_domain" {
  type        = string
  description = "Domain of the cluster (required for SSM port forwarding)."
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for infrastructure encryption (EBS volumes, CloudWatch logs). This is separate from the cluster KMS key."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
