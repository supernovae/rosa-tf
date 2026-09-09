variable "private_cluster" {
  type        = bool
  default     = true
  description = "GovCloud HCP deployments remain private."
  validation {
    condition     = var.private_cluster
    error_message = "GovCloud HCP requires private_cluster=true."
  }
}
variable "fips" {
  type        = bool
  default     = true
  description = "GovCloud HCP requires FIPS at creation."
  validation {
    condition     = var.fips
    error_message = "GovCloud HCP requires fips=true."
  }
}
variable "etcd_encryption" {
  type        = bool
  default     = true
  description = "GovCloud HCP etcd encryption remains enabled."
  validation {
    condition     = var.etcd_encryption
    error_message = "GovCloud HCP requires etcd_encryption=true."
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

variable "cluster_delete_protection" {
  type        = bool
  description = "OCM deletion protection; disable only in a separately reviewed decommission apply."
  default     = true
}
resource "terraform_data" "deployment_safety" {
  lifecycle {

    precondition {
      condition = var.machine_pool_version == null ? true : try(
        tonumber(split(".", var.machine_pool_version)[0]) == tonumber(split(".", module.rosa_cluster.current_version)[0]) &&
        tonumber(split(".", var.machine_pool_version)[1]) <= tonumber(split(".", module.rosa_cluster.current_version)[1]) &&
        tonumber(split(".", var.machine_pool_version)[1]) >= tonumber(split(".", module.rosa_cluster.current_version)[1]) - 2 &&
        (tonumber(split(".", var.machine_pool_version)[1]) != tonumber(split(".", module.rosa_cluster.current_version)[1]) ||
      tonumber(split(".", var.machine_pool_version)[2]) <= tonumber(split(".", module.rosa_cluster.current_version)[2])), false)
      error_message = "HCP pools must not be newer than the control plane or more than two minors behind it."
    }
  }
}
module "component_routes" {
  source                 = "../../modules/cluster/component-routes"
  count                  = var.install_gitops && length(var.component_routes) > 0 ? 1 : 0
  cluster_id             = module.rosa_cluster.cluster_id
  cluster_type           = "hcp"
  private_cluster        = var.private_cluster
  component_routes       = var.component_routes
  component_routes_ready = var.component_routes_ready
  depends_on             = [module.gitops]
}
