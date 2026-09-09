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

variable "cluster_id" { type = string }
variable "cluster_type" {
  type = string
  validation {
    condition     = contains(["classic", "hcp"], var.cluster_type)
    error_message = "Cluster type must be classic or hcp."
  }
}
variable "private_cluster" { type = bool }
