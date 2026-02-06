#------------------------------------------------------------------------------
# Additional Security Groups Module - Outputs
#------------------------------------------------------------------------------

output "compute_security_group_ids" {
  description = <<-EOT
    List of security group IDs to attach to compute/worker nodes.
    Combines existing IDs (if provided) with any created by this module.
    Pass this to the ROSA cluster module's aws_additional_compute_security_group_ids.
  EOT
  value       = local.compute_security_group_ids
}

output "control_plane_security_group_ids" {
  description = <<-EOT
    (Classic only) List of security group IDs to attach to control plane nodes.
    Combines existing IDs (if provided) with any created by this module.
    Pass this to the ROSA cluster module's aws_additional_control_plane_security_group_ids.
    Empty for HCP clusters.
  EOT
  value       = local.control_plane_security_group_ids
}

output "infra_security_group_ids" {
  description = <<-EOT
    (Classic only) List of security group IDs to attach to infrastructure nodes.
    Combines existing IDs (if provided) with any created by this module.
    Pass this to the ROSA cluster module's aws_additional_infra_security_group_ids.
    Empty for HCP clusters.
  EOT
  value       = local.infra_security_group_ids
}

#------------------------------------------------------------------------------
# Individual Security Group Details
#------------------------------------------------------------------------------

output "created_compute_sg_id" {
  description = "ID of the created compute security group (if any)."
  value       = local.create_compute_sg ? aws_security_group.compute[0].id : null
}

output "created_compute_sg_arn" {
  description = "ARN of the created compute security group (if any)."
  value       = local.create_compute_sg ? aws_security_group.compute[0].arn : null
}

output "created_control_plane_sg_id" {
  description = "(Classic only) ID of the created control plane security group (if any)."
  value       = local.create_control_plane_sg ? aws_security_group.control_plane[0].id : null
}

output "created_control_plane_sg_arn" {
  description = "(Classic only) ARN of the created control plane security group (if any)."
  value       = local.create_control_plane_sg ? aws_security_group.control_plane[0].arn : null
}

output "created_infra_sg_id" {
  description = "(Classic only) ID of the created infra security group (if any)."
  value       = local.create_infra_sg ? aws_security_group.infra[0].id : null
}

output "created_infra_sg_arn" {
  description = "(Classic only) ARN of the created infra security group (if any)."
  value       = local.create_infra_sg ? aws_security_group.infra[0].arn : null
}

#------------------------------------------------------------------------------
# Summary Output
#------------------------------------------------------------------------------

output "summary" {
  description = "Summary of security group configuration."
  value = {
    enabled                          = var.enabled
    cluster_type                     = var.cluster_type
    use_intra_vpc_template           = var.use_intra_vpc_template
    compute_sg_count                 = length(local.compute_security_group_ids)
    control_plane_sg_count           = length(local.control_plane_security_group_ids)
    infra_sg_count                   = length(local.infra_security_group_ids)
    compute_security_group_ids       = local.compute_security_group_ids
    control_plane_security_group_ids = local.control_plane_security_group_ids
    infra_security_group_ids         = local.infra_security_group_ids
  }
}
