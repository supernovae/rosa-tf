#------------------------------------------------------------------------------
# Cluster Auth Module Variables
#------------------------------------------------------------------------------

variable "enabled" {
  type        = bool
  description = <<-EOT
    Enable authentication token retrieval.
    Set to false to skip authentication (e.g., when cluster doesn't exist yet).
  EOT
  default     = true
}

variable "api_url" {
  type        = string
  description = <<-EOT
    OpenShift API server URL.
    Example: https://api.cluster-name.region.p1.openshiftapps.com:6443
  EOT
}

variable "oauth_url" {
  type        = string
  description = <<-EOT
    OAuth server URL (optional). If not provided, derived from api_url.
    
    The default derivation assumes standard OpenShift 4.x layout:
      API URL:   https://api.<cluster>.<domain>:6443
      OAuth URL: https://oauth-openshift.apps.<cluster>.<domain>
    
    Override this if:
    - Using HCP with external authentication
    - Using a non-standard OAuth configuration
    - Older OpenShift versions with different OAuth routing
    
    Discovery command:
      oc get route -n openshift-authentication oauth-openshift -o jsonpath='{.spec.host}'
  EOT
  default     = ""
}

variable "cluster_token" {
  type        = string
  description = <<-EOT
    Pre-provided cluster authentication token (optional).
    
    If set, skips OAuth token retrieval and uses this token directly.
    Useful for:
    - HCP clusters with external authentication (OIDC, LDAP)
    - Service account tokens
    - Scenarios where htpasswd IDP is not available
    
    To obtain a token manually:
      oc login <cluster> -u <user> -p <password>
      oc whoami -t
  EOT
  default     = ""
  sensitive   = true
}

variable "username" {
  type        = string
  description = <<-EOT
    Username for authentication.
    Must be a valid user in the htpasswd identity provider.
    Ignored if cluster_token is provided.
  EOT
  default     = ""
}

variable "password" {
  type        = string
  description = <<-EOT
    Password for authentication.
    This is the password configured in the htpasswd identity provider.
    Ignored if cluster_token is provided.
  EOT
  default     = ""
  sensitive   = true
}
