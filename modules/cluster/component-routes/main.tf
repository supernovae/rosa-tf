# One owner of native OCM ingress; separate from cert-manager custom application ingress.
resource "rhcs_hcp_default_ingress" "this" {
  count            = var.cluster_type == "hcp" && length(var.component_routes) > 0 ? 1 : 0
  cluster          = var.cluster_id
  listening_method = var.private_cluster ? "internal" : "external"
  component_routes = var.component_routes
  lifecycle {
    precondition {
      condition     = var.component_routes_ready && !contains(keys(var.component_routes), "oauth")
      error_message = "HCP supports console/downloads only; confirm DNS, TLS and ingress ownership first."
    }
  }
}
resource "rhcs_default_ingress" "this" {
  count                            = var.cluster_type == "classic" && length(var.component_routes) > 0 ? 1 : 0
  cluster                          = var.cluster_id
  component_routes                 = var.component_routes
  route_namespace_ownership_policy = "Strict"
  route_wildcard_policy            = "WildcardsDisallowed"
  lifecycle {
    precondition {
      condition     = var.component_routes_ready
      error_message = "Confirm trusted TLS Secrets, DNS and default-ingress ownership before changing Classic routes."
    }
  }
}
