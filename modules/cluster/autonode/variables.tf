#------------------------------------------------------------------------------
# AutoNode (Karpenter) Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA HCP cluster."
}

variable "cluster_id" {
  type        = string
  description = <<-EOT
    OCM cluster ID (the internal identifier, not the cluster name).
    Used as the value for karpenter.sh/discovery subnet tags.
  EOT
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

variable "private_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    List of private subnet IDs to tag with Karpenter discovery tags.
    These subnets will be used by Karpenter for node placement.
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
