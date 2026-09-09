#------------------------------------------------------------------------------
# AutoNode (Karpenter) Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA HCP cluster."
}


variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    OIDC endpoint URL (without https://).
    Used to build the trust policy for the Karpenter IAM role.
    Obtain from: module.iam_roles.oidc_endpoint_url
  EOT
}

variable "operator_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix used for ROSA operator IAM roles.
    Typically the cluster name. Used to find the
    {prefix}-kube-system-control-plane-operator role.
  EOT
}


variable "enable_ecr_pull" {
  type        = bool
  description = "Attach ECR pull policy to the Karpenter role for OCI image access."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to created resources."
  default     = {}
}
