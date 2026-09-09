mock_provider "rhcs" {}
variables {
  cluster_id             = "test-cluster"
  cluster_type           = "hcp"
  private_cluster        = true
  component_routes_ready = true
  component_routes       = { console = { hostname = "console.example.com", tls_secret_ref = "console-tls" } }
}
run "private_hcp_console" {
  command = plan
  assert {
    condition     = rhcs_hcp_default_ingress.this[0].listening_method == "internal" && rhcs_hcp_default_ingress.this[0].component_routes["console"].tls_secret_ref == "console-tls"
    error_message = "Preserve private ingress and TLS Secret references."
  }
}
run "classic_oauth" {
  command = plan
  variables {
    cluster_type     = "classic"
    component_routes = { oauth = { hostname = "oauth.example.com", tls_secret_ref = "oauth-tls" } }
  }
  assert {
    condition     = rhcs_default_ingress.this[0].route_namespace_ownership_policy == "Strict" && rhcs_default_ingress.this[0].route_wildcard_policy == "WildcardsDisallowed"
    error_message = "Classic component routes must preserve strict namespace and wildcard policy."
  }
}
run "reject_hcp_oauth" {
  command = plan
  variables { component_routes = { oauth = { hostname = "oauth.example.com", tls_secret_ref = "oauth-tls" } } }
  expect_failures = [rhcs_hcp_default_ingress.this]
}
run "reject_unprepared_routes" {
  command = plan
  variables { component_routes_ready = false }
  expect_failures = [rhcs_hcp_default_ingress.this]
}
run "reject_wildcard_host" {
  command = plan
  variables { component_routes = { console = { hostname = "*.example.com", tls_secret_ref = "console-tls" } } }
  expect_failures = [var.component_routes]
}
