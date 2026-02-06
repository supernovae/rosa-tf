#------------------------------------------------------------------------------
# KMS Module Outputs
#
# Two separate keys with strict separation:
# - cluster_kms_key_arn: For ROSA workers and etcd ONLY
# - infra_kms_key_arn: For jump host, CloudWatch, S3, VPN ONLY
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster KMS Key Outputs
#------------------------------------------------------------------------------

output "cluster_kms_key_arn" {
  description = <<-EOT
    ARN of the KMS key for ROSA cluster encryption (workers, etcd).
    - provider_managed mode: null (uses AWS managed aws/ebs key)
    - create mode: ARN of the created customer-managed key
    - existing mode: ARN of the provided key
    
    IMPORTANT: Use this ONLY for ROSA resources (worker EBS, etcd).
    Do NOT use for jump host, CloudWatch, S3, or other infrastructure.
  EOT
  value       = local.cluster_kms_key_arn
}

output "cluster_kms_key_id" {
  description = "ID of the cluster KMS key (only set when cluster_kms_mode = 'create')."
  value       = local.create_cluster_key ? aws_kms_key.cluster[0].key_id : null
}

output "cluster_kms_key_alias" {
  description = "Alias of the cluster KMS key (only set when cluster_kms_mode = 'create')."
  value       = local.create_cluster_key ? aws_kms_alias.cluster[0].name : null
}

output "cluster_kms_mode" {
  description = "The cluster KMS mode being used: provider_managed, create, or existing."
  value       = var.cluster_kms_mode
}

#------------------------------------------------------------------------------
# Infrastructure KMS Key Outputs
#------------------------------------------------------------------------------

output "infra_kms_key_arn" {
  description = <<-EOT
    ARN of the KMS key for infrastructure encryption (non-ROSA resources).
    - provider_managed mode: null (uses AWS managed aws/ebs key)
    - create mode: ARN of the created customer-managed key
    - existing mode: ARN of the provided key
    
    Use this for:
    - Jump host EBS volumes
    - CloudWatch log encryption
    - S3 bucket encryption (OADP, backups)
    - VPN connection logs
    
    IMPORTANT: Do NOT use this for ROSA workers - use cluster_kms_key_arn instead.
  EOT
  value       = local.infra_kms_key_arn
}

output "infra_kms_key_id" {
  description = "ID of the infrastructure KMS key (only set when infra_kms_mode = 'create')."
  value       = local.create_infra_key ? aws_kms_key.infrastructure[0].key_id : null
}

output "infra_kms_key_alias" {
  description = "Alias of the infrastructure KMS key (only set when infra_kms_mode = 'create')."
  value       = local.create_infra_key ? aws_kms_alias.infrastructure[0].name : null
}

output "infra_kms_mode" {
  description = "The infrastructure KMS mode being used: provider_managed, create, or existing."
  value       = var.infra_kms_mode
}

#------------------------------------------------------------------------------
# Summary Outputs
#------------------------------------------------------------------------------

output "kms_summary" {
  description = "Summary of KMS configuration for both cluster and infrastructure keys."
  value = {
    cluster = {
      mode      = var.cluster_kms_mode
      key_arn   = local.cluster_kms_key_arn
      key_alias = local.create_cluster_key ? aws_kms_alias.cluster[0].name : null
      scope     = "ROSA workers, etcd"
      description = (
        var.cluster_kms_mode == "provider_managed" ? "Using AWS managed aws/ebs key" :
        var.cluster_kms_mode == "create" ? "Using Terraform-managed customer key" :
        "Using customer-provided key"
      )
    }
    infrastructure = {
      mode      = var.infra_kms_mode
      key_arn   = local.infra_kms_key_arn
      key_alias = local.create_infra_key ? aws_kms_alias.infrastructure[0].name : null
      scope     = "Jump host, CloudWatch, S3, VPN"
      description = (
        var.infra_kms_mode == "provider_managed" ? "Using AWS managed aws/ebs key" :
        var.infra_kms_mode == "create" ? "Using Terraform-managed customer key" :
        "Using customer-provided key"
      )
    }
    separation_enforced = true
  }
}
