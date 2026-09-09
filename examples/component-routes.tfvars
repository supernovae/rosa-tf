# Phase 2 overlay for native OCM routes, not custom application ingress.
# Before setting ready=true: create trusted TLS Secrets in openshift-config,
# validate DNS/certificates and confirm ownership/eligibility of default ingress.
install_gitops         = true
component_routes_ready = false
component_routes = {
  console   = { hostname = "console.example.com", tls_secret_ref = "console-tls" }
  downloads = { hostname = "downloads.example.com", tls_secret_ref = "downloads-tls" }
  # Classic only: oauth = { hostname = "oauth.example.com", tls_secret_ref = "oauth-tls" }
}
