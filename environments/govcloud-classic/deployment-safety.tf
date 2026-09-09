variable "private_cluster" {
  type        = bool
  default     = true
  description = "GovCloud Classic deployments remain private."
  validation {
    condition     = var.private_cluster
    error_message = "GovCloud Classic requires private_cluster=true."
  }
}
variable "fips" {
  type        = bool
  default     = true
  description = "GovCloud Classic requires FIPS at cluster creation."
  validation {
    condition     = var.fips
    error_message = "GovCloud Classic requires fips=true."
  }
}

variable "component_routes" {
  description = "Native OCM component routes; TLS Secret references only, never certificate/key contents."
  type        = map(object({ hostname = string, tls_secret_ref = string }))
  default     = {}
  validation {
    condition = alltrue([for key, route in var.component_routes :
      contains(["console", "downloads", "oauth"], key) &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?([.][a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", route.hostname)) &&
      can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", route.tls_secret_ref))
    ]) && length(distinct([for route in values(var.component_routes) : route.hostname])) == length(var.component_routes)
    error_message = "Use console/downloads/oauth keys, unique DNS hostnames and valid existing TLS Secret names."
  }
}
variable "component_routes_ready" {
  type        = bool
  default     = false
  description = "Confirm trusted TLS Secrets, DNS, platform eligibility and ownership of native default-ingress configuration before applying."
}

variable "allow_prerelease_provider" {
  type        = bool
  description = "Explicit development-only acknowledgment; RHCS prereleases are not production releases."
  default     = false
}
variable "cluster_delete_protection" {
  type        = bool
  description = "OCM deletion protection; disable only in a separately reviewed decommission apply."
  default     = true
}
locals { release_status = jsondecode(file("${path.module}/../../release-status.json")) }
resource "terraform_data" "deployment_safety" {
  lifecycle {
    precondition {
      condition     = !strcontains(local.release_status.rhcs_version, "-") || var.allow_prerelease_provider
      error_message = "This 2.0 development branch pins prerelease RHCS. Explicitly acknowledge development use with allow_prerelease_provider=true; do not use it as a production release."
    }
  }
}
module "component_routes" {
  source                 = "../../modules/cluster/component-routes"
  count                  = var.install_gitops && length(var.component_routes) > 0 ? 1 : 0
  cluster_id             = module.rosa_cluster.cluster_id
  cluster_type           = "classic"
  private_cluster        = var.private_cluster
  component_routes       = var.component_routes
  component_routes_ready = var.component_routes_ready
  depends_on             = [module.gitops]
}
