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
# DNSSEC
#------------------------------------------------------------------------------

output "dnssec_enabled" {
  description = "Whether DNSSEC signing is enabled on the hosted zone."
  value       = var.create_hosted_zone && var.enable_dnssec
}

output "dnssec_ds_record" {
  description = <<-EOT
    DS record value to add to the parent zone (domain registrar) to complete
    the DNSSEC chain of trust. Only populated when DNSSEC is enabled.
    
    Add this as a DS record at your domain registrar for the hosted zone domain.
  EOT
  value       = var.create_hosted_zone && var.enable_dnssec ? aws_route53_key_signing_key.certmanager[0].ds_record : ""
}

output "dnssec_kms_key_arn" {
  description = "ARN of the KMS key used for DNSSEC Key Signing Key."
  value       = var.create_hosted_zone && var.enable_dnssec ? aws_kms_key.dnssec[0].arn : ""
}

output "query_logging_enabled" {
  description = "Whether DNS query logging is enabled on the hosted zone."
  value       = var.create_hosted_zone && var.enable_query_logging
}

output "query_log_group_arn" {
  description = "ARN of the CloudWatch log group for DNS query logs."
  value       = var.create_hosted_zone && var.enable_query_logging ? aws_cloudwatch_log_group.query_logging[0].arn : ""
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
