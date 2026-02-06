#------------------------------------------------------------------------------
# Cluster Auth Module
#
# Obtains an OAuth bearer token for OpenShift cluster authentication.
# Supports multiple authentication methods:
#
# 1. htpasswd IDP (default): Uses username/password to get OAuth token
# 2. User-provided token: Directly use a pre-obtained token
# 3. Custom OAuth URL: Override for HCP external auth or older versions
#
# IMPORTANT: This module requires:
# 1. The cluster to be fully provisioned and accessible
# 2. Either htpasswd IDP credentials OR a pre-provided token
# 3. curl to be available on the system running Terraform
#
# The token obtained is short-lived and will be refreshed on each Terraform run.
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
