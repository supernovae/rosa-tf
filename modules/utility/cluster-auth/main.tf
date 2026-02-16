#------------------------------------------------------------------------------
# Cluster Auth Module -- Bootstrap Only
#
# Obtains an OAuth bearer token for the initial GitOps bootstrap (Phase 2).
# This token is used ONCE to create the Terraform operator ServiceAccount
# and its long-lived token. After bootstrap, subsequent Terraform runs
# authenticate with the SA token (gitops_cluster_token) and this module
# is no longer invoked.
#
# Authentication methods (in priority order):
#   1. User-provided token (gitops_cluster_token) -- skips OAuth entirely
#   2. htpasswd IDP credentials -- uses OAuth ROPC flow to get bearer token
#   3. Custom OAuth URL override -- for non-standard configurations
#
# Once the SA token exists in state, the htpasswd IDP can be safely removed
# or replaced with a production IDP (LDAP, OIDC, etc.) without affecting
# Terraform operations. See OPERATIONS.md for token rotation guidance.
#
# Requirements:
#   - Cluster must be fully provisioned and API-accessible
#   - curl must be available on the system running Terraform
#------------------------------------------------------------------------------

locals {
  # Normalize API URL (remove trailing slash if present)
  api_url = trimsuffix(var.api_url, "/")

  # Check if user provided their own token
  use_provided_token = var.cluster_token != ""
}

#------------------------------------------------------------------------------
# Get OAuth Token via curl (if not using provided token)
#
# Uses the Resource Owner Password Credentials (ROPC) flow to obtain a token.
# This is wrapped in an external data source to handle errors gracefully.
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
