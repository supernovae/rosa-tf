# Overlay on an approved cluster base; never a standalone cluster configuration.
# Confirm supported regional catalog/images, EFS and AWS Backup availability.
install_gitops           = true
enable_layer_efs_storage = true
efs_storage_class_name   = "efs-rwx-retain"
efs_performance_mode     = "generalPurpose"
efs_throughput_mode      = "elastic"
efs_encrypted            = true
efs_config = {
  install_plan_approval = "Manual"
  # Replace with the actual SGs on EVERY EFS-consuming worker pool/autoscaler.
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  # Set false when another manager already owns an all-namespaces OperatorGroup
  # in openshift-cluster-csi-drivers; do not create a second OperatorGroup there.
  manage_operator_group = true
}
