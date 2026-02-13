#------------------------------------------------------------------------------
# GitOps Layer Resources Module - Outputs
#
# These outputs provide all the configuration the gitops-layers/operator
# module needs to deploy and configure the enabled layers.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# OADP Outputs
#------------------------------------------------------------------------------

output "oadp_bucket_name" {
  description = "S3 bucket name for OADP backups."
  value       = var.enable_layer_oadp ? module.oadp[0].bucket_name : ""
}

output "oadp_bucket_arn" {
  description = "S3 bucket ARN for OADP backups."
  value       = var.enable_layer_oadp ? module.oadp[0].bucket_arn : ""
}

output "oadp_role_arn" {
  description = "IAM role ARN for OADP/Velero."
  value       = var.enable_layer_oadp ? module.oadp[0].role_arn : ""
}

output "oadp_role_name" {
  description = "IAM role name for OADP/Velero."
  value       = var.enable_layer_oadp ? module.oadp[0].role_name : ""
}

#------------------------------------------------------------------------------
# Monitoring Outputs
#------------------------------------------------------------------------------

output "monitoring_bucket_name" {
  description = "S3 bucket name for Loki logs."
  value       = var.enable_layer_monitoring ? module.monitoring[0].loki_bucket_name : ""
}

output "monitoring_bucket_arn" {
  description = "S3 bucket ARN for Loki logs."
  value       = var.enable_layer_monitoring ? module.monitoring[0].loki_bucket_arn : ""
}

output "monitoring_role_arn" {
  description = "IAM role ARN for Loki."
  value       = var.enable_layer_monitoring ? module.monitoring[0].loki_role_arn : ""
}

#------------------------------------------------------------------------------
# Cert-Manager Outputs
#------------------------------------------------------------------------------

output "certmanager_role_arn" {
  description = "IAM role ARN for cert-manager."
  value       = var.enable_layer_certmanager ? module.certmanager[0].certmanager_role_arn : ""
}

output "certmanager_hosted_zone_id" {
  description = "Route53 hosted zone ID for DNS01 challenges."
  value       = var.enable_layer_certmanager ? module.certmanager[0].hosted_zone_id : ""
}

output "certmanager_hosted_zone_domain" {
  description = "Domain of the Route53 hosted zone."
  value       = var.enable_layer_certmanager ? module.certmanager[0].hosted_zone_domain : ""
}

output "certmanager_hosted_zone_nameservers" {
  description = "Nameservers for the hosted zone (only populated when zone is created)."
  value       = var.enable_layer_certmanager ? module.certmanager[0].hosted_zone_nameservers : []
}

output "certmanager_dnssec_enabled" {
  description = "Whether DNSSEC signing is enabled on the cert-manager hosted zone."
  value       = var.enable_layer_certmanager ? module.certmanager[0].dnssec_enabled : false
}

output "certmanager_dnssec_ds_record" {
  description = "DS record to add to parent zone for DNSSEC chain of trust."
  value       = var.enable_layer_certmanager ? module.certmanager[0].dnssec_ds_record : ""
}

output "certmanager_ingress_enabled" {
  description = "Whether a custom IngressController is being created."
  value       = var.enable_layer_certmanager ? module.certmanager[0].ingress_enabled : false
}

output "certmanager_ingress_domain" {
  description = "Domain served by the custom IngressController."
  value       = var.enable_layer_certmanager ? module.certmanager[0].ingress_domain : ""
}

output "certmanager_ingress_visibility" {
  description = "Visibility of the custom IngressController NLB."
  value       = var.enable_layer_certmanager ? module.certmanager[0].ingress_visibility : ""
}

#------------------------------------------------------------------------------
# Summary Output (for debugging)
#------------------------------------------------------------------------------

output "enabled_layers" {
  description = "List of enabled layers."
  value = compact([
    var.enable_layer_terminal ? "terminal" : "",
    var.enable_layer_oadp ? "oadp" : "",
    var.enable_layer_virtualization ? "virtualization" : "",
    var.enable_layer_monitoring ? "monitoring" : "",
    var.enable_layer_certmanager ? "certmanager" : "",
  ])
}

output "layer_config" {
  description = "Complete layer configuration for operator module."
  value = {
    # Layer flags
    enable_terminal       = var.enable_layer_terminal
    enable_oadp           = var.enable_layer_oadp
    enable_virtualization = var.enable_layer_virtualization
    enable_monitoring     = var.enable_layer_monitoring

    # OADP config
    oadp_bucket_name           = var.enable_layer_oadp ? module.oadp[0].bucket_name : ""
    oadp_role_arn              = var.enable_layer_oadp ? module.oadp[0].role_arn : ""
    oadp_backup_retention_days = var.oadp_backup_retention_days

    # Monitoring config
    monitoring_bucket_name    = var.enable_layer_monitoring ? module.monitoring[0].loki_bucket_name : ""
    monitoring_role_arn       = var.enable_layer_monitoring ? module.monitoring[0].loki_role_arn : ""
    monitoring_retention_days = var.monitoring_retention_days

    # Cert-Manager config
    enable_certmanager             = var.enable_layer_certmanager
    certmanager_role_arn           = var.enable_layer_certmanager ? module.certmanager[0].certmanager_role_arn : ""
    certmanager_hosted_zone_id     = var.enable_layer_certmanager ? module.certmanager[0].hosted_zone_id : ""
    certmanager_hosted_zone_domain = var.enable_layer_certmanager ? module.certmanager[0].hosted_zone_domain : ""
  }
}

#------------------------------------------------------------------------------
# S3 Bucket Cleanup Notice
#
# S3 buckets are NOT automatically deleted on terraform destroy to prevent
# accidental data loss. Users must manually clean up buckets.
#------------------------------------------------------------------------------

output "s3_buckets_requiring_manual_cleanup" {
  description = <<-EOT
    S3 buckets created by GitOps layers that are retained on destroy.
    
    These buckets use CloudFormation DeletionPolicy: Retain, so they
    survive terraform destroy to protect log and backup data. During
    destroy, Terraform prints cleanup commands for each bucket.
    
    To delete manually when you no longer need the data:
      1. Empty the bucket (including version markers)
      2. Delete the bucket: aws s3 rb s3://BUCKET_NAME
  EOT
  value = compact([
    var.enable_layer_oadp ? module.oadp[0].bucket_name : "",
    var.enable_layer_monitoring ? module.monitoring[0].loki_bucket_name : "",
  ])
}
