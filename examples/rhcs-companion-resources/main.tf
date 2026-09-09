# Add these native resources alongside a cluster module, or manage them in a
# separately secured state with its cluster_id as input. They do not create a cluster.
terraform {
  required_version = ">= 1.16.1, < 2.0.0"
  required_providers {
    rhcs = { source = "terraform-redhat/rhcs", version = "= 1.7.8" }
  }
}
variable "cluster_id" { type = string }
variable "configure_identity" {
  type    = bool
  default = false
}
variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = null
}
# For a cluster using built-in OpenShift OAuth, not HCP external-auth mode.
# Replace issuer/client values, deliver the secret through approved runner auth,
# and protect the state; this configuration contains the IdP client secret.
resource "rhcs_identity_provider" "organization" {
  count          = var.configure_identity ? 1 : 0
  cluster        = var.cluster_id
  name           = "organization"
  mapping_method = "claim"
  openid = {
    issuer        = "https://identity.example.com"
    client_id     = "rosa-workloads"
    client_secret = var.oidc_client_secret
    claims        = { preferred_username = ["preferred_username"], name = ["name"], email = ["email"] }
  }
}
# Example for a prepared HCP pool. Reference the NAME from machine_pools[*].kubelet_configs.
resource "rhcs_kubeletconfig" "bounded_pids" {
  cluster        = var.cluster_id
  name           = "bounded-pids"
  pod_pids_limit = 4096
}
# Digest mirrors do not mirror content themselves. Populate the approved mirror
# first, preserve digest provenance, and ensure trusted TLS and private access.
resource "rhcs_image_mirror" "application" {
  cluster_id = var.cluster_id
  type       = "digest"
  source     = "registry.example.com/team"
  mirrors    = ["mirror.example.com/team"]
}
