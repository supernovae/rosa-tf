#------------------------------------------------------------------------------
# Cluster Auth Module Outputs
#------------------------------------------------------------------------------

output "token" {
  description = <<-EOT
    OAuth bearer token for cluster authentication.
    Empty string if authentication failed or was not attempted.
  EOT
  value       = local.token
  sensitive   = true
}

output "host" {
  description = <<-EOT
    Cluster API URL (passthrough for convenience).
    Use this as the 'host' parameter for kubernetes provider.
  EOT
  value       = var.enabled ? local.api_url : ""
}

output "authenticated" {
  description = <<-EOT
    Whether authentication was successful.
    Use this to conditionally enable kubernetes-dependent resources.
  EOT
  value       = local.authenticated
}

output "error" {
  description = <<-EOT
    Error message if authentication failed.
    Empty string if successful or not attempted.
  EOT
  value       = local.error
}

output "auth_summary" {
  description = "Summary of authentication status for debugging."
  value = {
    enabled       = var.enabled
    authenticated = local.authenticated
    host          = var.enabled ? local.api_url : ""
    username      = var.username
    error         = local.error
  }
}
