#------------------------------------------------------------------------------
# Cert-Manager Resources Module Outputs
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# IAM Role
#------------------------------------------------------------------------------

output "certmanager_role_arn" {
  description = "ARN of the IAM role for cert-manager."
  value       = aws_iam_role.certmanager.arn
}

output "certmanager_role_name" {
  description = "Name of the IAM role for cert-manager."
  value       = aws_iam_role.certmanager.name
}

#------------------------------------------------------------------------------
# Route53 Hosted Zone
#------------------------------------------------------------------------------

output "hosted_zone_id" {
  description = "ID of the Route53 hosted zone used for DNS01 challenges."
  value       = local.effective_hosted_zone_id
}

output "hosted_zone_domain" {
  description = "Domain of the Route53 hosted zone."
  value       = local.effective_hosted_zone_domain
}

output "hosted_zone_nameservers" {
  description = <<-EOT
    Nameservers for the Route53 hosted zone (only populated when zone is created).
    Configure your domain registrar to delegate DNS to these nameservers.
  EOT
  value       = var.create_hosted_zone ? aws_route53_zone.certmanager[0].name_servers : []
}

#------------------------------------------------------------------------------
# Summary for GitOps ConfigMap
#------------------------------------------------------------------------------

output "gitops_config" {
  description = "Configuration values to pass to GitOps layer."
  value = {
    role_arn       = aws_iam_role.certmanager.arn
    hosted_zone_id = local.effective_hosted_zone_id
    domain         = local.effective_hosted_zone_domain
    aws_region     = var.aws_region
    is_govcloud    = var.is_govcloud
  }
}
