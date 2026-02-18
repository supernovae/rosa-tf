#------------------------------------------------------------------------------
# NetApp Storage (FSx ONTAP) Resources Module - Outputs
#------------------------------------------------------------------------------

output "filesystem_id" {
  description = "FSx ONTAP file system ID."
  value       = aws_fsx_ontap_file_system.this.id
}

output "filesystem_dns_name" {
  description = "DNS name for the FSx ONTAP file system management endpoint."
  value       = aws_fsx_ontap_file_system.this.dns_name
}

output "svm_id" {
  description = "Storage Virtual Machine ID."
  value       = aws_fsx_ontap_storage_virtual_machine.this.id
}

output "svm_name" {
  description = "Storage Virtual Machine name."
  value       = aws_fsx_ontap_storage_virtual_machine.this.name
}

output "svm_management_endpoint" {
  description = "SVM management endpoint IP address(es). Used by Trident for backend configuration."
  value       = aws_fsx_ontap_storage_virtual_machine.this.endpoints[0].management[0].ip_addresses
}

output "svm_nfs_endpoint" {
  description = "SVM NFS endpoint IP address(es)."
  value       = aws_fsx_ontap_storage_virtual_machine.this.endpoints[0].nfs[0].ip_addresses
}

output "svm_iscsi_endpoint" {
  description = "SVM iSCSI endpoint IP address(es)."
  value       = aws_fsx_ontap_storage_virtual_machine.this.endpoints[0].iscsi[0].ip_addresses
}

output "security_group_id" {
  description = "Security group ID for FSx ONTAP access."
  value       = aws_security_group.fsx_ontap.id
}

output "trident_role_arn" {
  description = "IAM role ARN for Trident CSI controller (IRSA)."
  value       = aws_iam_role.trident_csi.arn
}

output "trident_role_name" {
  description = "IAM role name for Trident CSI controller."
  value       = aws_iam_role.trident_csi.name
}

output "dedicated_subnet_ids" {
  description = "Dedicated FSxN subnet IDs (empty if using ROSA subnets)."
  value       = aws_subnet.fsx_ontap[*].id
}

output "gitops_config" {
  description = "Configuration values passed to the operator module for NetApp storage layer."
  value = {
    filesystem_id     = aws_fsx_ontap_file_system.this.id
    svm_management_ip = aws_fsx_ontap_storage_virtual_machine.this.endpoints[0].management[0].ip_addresses[0]
    trident_role_arn  = aws_iam_role.trident_csi.arn
    security_group_id = aws_security_group.fsx_ontap.id
  }
}

output "ready" {
  description = "Indicates that NetApp storage resources are ready."
  value       = true
  depends_on  = [time_sleep.role_propagation]
}
