#------------------------------------------------------------------------------
# Custom Ingress Module Variables
#------------------------------------------------------------------------------

variable "custom_domain" {
  type        = string
  description = "Custom domain for the secondary ingress (e.g., apps.mydomain.com)."
}

variable "replicas" {
  type        = number
  description = "Number of replicas for the custom ingress controller."
  default     = 2
}

variable "route_selector" {
  type        = map(string)
  description = "Route label selector for the custom ingress. Only routes with these labels will use this ingress."
  default     = {}
}
