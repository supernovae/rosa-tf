#------------------------------------------------------------------------------
# ECR Module Outputs
#
# Note: This module is instantiated via count at the environment level.
# When this module exists, ECR is enabled - no internal conditionals needed.
#------------------------------------------------------------------------------

output "repository_url" {
  description = "URL of the ECR repository for docker push/pull."
  value       = local.ecr_repository.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository."
  value       = local.ecr_repository.arn
}

output "repository_name" {
  description = "Name of the ECR repository."
  value       = local.ecr_repository.name
}

output "registry_id" {
  description = "The registry ID (AWS account ID) where the repository was created."
  value       = local.ecr_repository.registry_id
}

output "registry_url" {
  description = "The ECR registry URL (without repository name) for docker login."
  value       = local.registry_url
}

output "prevent_destroy" {
  description = "Whether the ECR repository is protected from cluster destruction."
  value       = var.prevent_destroy
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

output "ecr_summary" {
  description = "Summary of ECR configuration."
  value = {
    repository_name = local.ecr_repository.name
    repository_url  = local.ecr_repository.repository_url
    registry_url    = local.registry_url
    encryption      = var.kms_key_arn != null ? "KMS" : "AES256"
    scan_on_push    = var.scan_on_push
    tag_mutability  = var.image_tag_mutability
    prevent_destroy = var.prevent_destroy
    lifecycle_note  = var.prevent_destroy ? "Protected - set prevent_destroy=false to remove" : "Standard - destroyed with cluster"
  }
}

#------------------------------------------------------------------------------
# IDMS (ImageDigestMirrorSet) Outputs
#------------------------------------------------------------------------------

output "idms_config_path" {
  description = "Path to the generated IDMS configuration file (null if not generated)."
  value       = var.generate_idms ? local_file.idms_config[0].filename : null
}

output "idms_config_content" {
  description = "Content of the IDMS configuration (for reference, apply via oc apply -f)."
  value       = var.generate_idms ? local.idms_content : null
}

#------------------------------------------------------------------------------
# VPC Endpoint Outputs
#------------------------------------------------------------------------------

output "ecr_api_endpoint_id" {
  description = "ID of the ECR API VPC endpoint."
  value       = local.create_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "ecr_dkr_endpoint_id" {
  description = "ID of the ECR DKR (Docker) VPC endpoint."
  value       = local.create_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

output "endpoint_security_group_id" {
  description = "ID of the security group for ECR endpoints (if created by this module)."
  value       = local.use_default_sg ? aws_security_group.ecr_endpoints[0].id : null
}

output "vpc_endpoints_enabled" {
  description = "Whether VPC endpoints for ECR were created."
  value       = local.create_endpoints
}
