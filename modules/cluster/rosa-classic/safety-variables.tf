variable "cluster_delete_protection" {
  type        = bool
  description = "OCM deletion protection. Disable only in a separately reviewed decommission apply."
  default     = true
}
