#------------------------------------------------------------------------------
# GitOps Module Outputs
#------------------------------------------------------------------------------

output "namespace" {
  description = "Namespace where GitOps operator is installed."
  value       = "openshift-gitops"
}

output "configmap_name" {
  description = "Name of the ConfigMap bridge for Terraform-to-GitOps communication."
  value       = "rosa-gitops-config"
}

output "configmap_namespace" {
  description = "Namespace of the ConfigMap bridge."
  value       = "openshift-gitops"
}

output "argocd_url" {
  description = "Command to get the ArgoCD console URL."
  value       = "oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'"
}

output "argocd_admin_password" {
  description = "Command to get the ArgoCD admin password."
  value       = "oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=- --keys=admin.password"
}

output "layers_enabled" {
  description = "Map of enabled GitOps layers."
  value = {
    terminal       = var.enable_layer_terminal
    oadp           = var.enable_layer_oadp
    virtualization = var.enable_layer_virtualization
    monitoring     = var.enable_layer_monitoring
    certmanager    = var.enable_layer_certmanager
  }
}

output "layers_repo" {
  description = "GitOps layers repository configuration."
  value = {
    url      = var.gitops_repo_url
    revision = var.gitops_repo_revision
    path     = var.gitops_repo_path
  }
}

output "applicationset_deployed" {
  description = "Whether a custom GitOps ApplicationSet was deployed."
  value       = local.has_custom_gitops_repo && local.appset_layer_elements != ""
}

output "install_instructions" {
  description = "Instructions for accessing GitOps."
  value       = <<-EOT
    
    OpenShift GitOps has been installed by Terraform.
    
    Access ArgoCD:
    1. Get the route:
       oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
    
    2. Login options:
       - Use OpenShift OAuth (click "Log in via OpenShift")
       - Or get admin password:
         oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=- --keys=admin.password
    
    Enabled Layers:
    - Terminal: ${var.enable_layer_terminal}
    - OADP: ${var.enable_layer_oadp}
    - Virtualization: ${var.enable_layer_virtualization}
    - Monitoring: ${var.enable_layer_monitoring}
    - Cert-Manager: ${var.enable_layer_certmanager}
    
    ConfigMap Bridge:
    The ConfigMap 'rosa-gitops-config' in namespace 'openshift-gitops' contains
    cluster metadata and layer configuration that ArgoCD uses to manage layers.
    
    To modify layer settings, update the Terraform variables and re-apply.
    
  EOT
}
