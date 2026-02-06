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
# Summary Output (for debugging)
#------------------------------------------------------------------------------

output "enabled_layers" {
  description = "List of enabled layers."
  value = compact([
    var.enable_layer_terminal ? "terminal" : "",
    var.enable_layer_oadp ? "oadp" : "",
    var.enable_layer_virtualization ? "virtualization" : "",
    var.enable_layer_monitoring ? "monitoring" : "",
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
    S3 buckets created by GitOps layers that require manual cleanup.
    
    IMPORTANT: These buckets are NOT deleted by terraform destroy to prevent
    accidental data loss. After destroying the cluster, manually delete these
    buckets if you no longer need the data:
    
    To delete (AWS CLI):
      aws s3 rb s3://BUCKET_NAME --force
    
    Or via AWS Console: Empty bucket contents first, then delete bucket.
  EOT
  value = compact([
    var.enable_layer_oadp ? module.oadp[0].bucket_name : "",
    var.enable_layer_monitoring ? module.monitoring[0].loki_bucket_name : "",
  ])
}
