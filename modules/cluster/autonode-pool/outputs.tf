#------------------------------------------------------------------------------
# AutoNode Pool Module Outputs
#------------------------------------------------------------------------------

output "nodepool_names" {
  description = "Names of the created Karpenter NodePool resources."
  value       = [for name, _ in kubectl_manifest.nodepool : name]
}
