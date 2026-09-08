# Verified-TLS OAuth challenge bootstrap, used only without a provided runner token.
# Requires curl and jq. Discovery and authorization failures stop the apply.
# Prefer short-lived credentials from an approved runner identity for later runs.
# Retire htpasswd only after independent IdP/runner access has been verified.
# See docs/GITOPS.md; credentials and external-data results are sensitive state.

locals {
  # Normalize API URL (remove trailing slash if present)
  api_url = trimsuffix(var.api_url, "/")

  # Check if user provided their own token
  use_provided_token = var.cluster_token != ""
}

#------------------------------------------------------------------------------
# Get OAuth Token via curl (if not using provided token)
#
# Uses the OpenShift OAuth challenging-client authorization flow.
# The external data source fails closed on authentication or TLS errors.
#
# NOTE: We pass credentials via stdin JSON to avoid shell escaping issues
# with special characters in passwords.
#------------------------------------------------------------------------------

data "external" "oauth_token" {
  count = var.enabled && !local.use_provided_token ? 1 : 0

  program = ["bash", "${path.module}/get-token.sh"]

  query = {
    api_url   = local.api_url
    oauth_url = var.oauth_url
    username  = var.username
    password  = var.password
  }
  lifecycle {
    postcondition {
      condition     = try(self.result.authenticated == "true" && self.result.token != "", false)
      error_message = "GitOps bootstrap failed. Verify private connectivity, trusted API/OAuth CAs and approved credentials; no unauthenticated fallback is permitted."
    }
  }
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

locals {
  # Extract results from external data source or use provided token
  result = var.enabled ? (
    local.use_provided_token ? {
      token         = var.cluster_token
      authenticated = "true"
      error         = ""
    } : data.external.oauth_token[0].result
  ) : {}

  token         = lookup(local.result, "token", "")
  authenticated = lookup(local.result, "authenticated", "false") == "true"
  error         = lookup(local.result, "error", "")
}
