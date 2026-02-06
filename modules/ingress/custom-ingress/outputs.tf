#------------------------------------------------------------------------------
# Custom Ingress Module Outputs
#------------------------------------------------------------------------------

output "ingress_name" {
  description = "Name of the custom IngressController."
  value       = local.ingress_name
}

output "ingress_domain" {
  description = "Domain configured for the custom ingress."
  value       = var.custom_domain
}

output "ingress_controller_manifest_path" {
  description = "Path to the IngressController manifest file."
  value       = local_file.ingress_controller_manifest.filename
}

output "certificate_secret_manifest_path" {
  description = "Path to the certificate secret template file."
  value       = local_file.certificate_secret_template.filename
}

output "sample_route_manifest_path" {
  description = "Path to the sample route manifest file."
  value       = local_file.sample_route_manifest.filename
}

output "dns_configuration_guide_path" {
  description = "Path to the DNS configuration guide."
  value       = local_file.dns_configuration_guide.filename
}

output "apply_instructions" {
  description = "Instructions for applying the custom ingress manifests."
  value       = <<-EOT
    
    To configure the custom ingress controller for ${var.custom_domain}:
    
    1. Apply the IngressController manifest:
       oc apply -f ${local_file.ingress_controller_manifest.filename}
    
    2. Wait for the router pods to be ready:
       oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=${local.ingress_name} -w
    
    3. Get the load balancer hostname:
       oc get svc -n openshift-ingress router-${local.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    
    4. Configure DNS (see ${local_file.dns_configuration_guide.filename})
    
    5. (Optional) Configure TLS certificate:
       - Edit ${local_file.certificate_secret_template.filename}
       - Apply: oc apply -f ${local_file.certificate_secret_template.filename}
    
  EOT
}

output "load_balancer_hostname" {
  description = "Placeholder for load balancer hostname (retrieve after applying manifest)."
  value       = "Run: oc get svc -n openshift-ingress router-${local.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
