# NetApp storage overlay for all four roots. Apply AFTER cluster provisioning.
# Read docs/NETAPP-STORAGE.md; this sample requires real CA/endpoint/Secret inputs.
# Supply separate TF_VAR_fsx_admin_password and TF_VAR_fsx_svm_password through
# your secret-managed runner. Never put passwords or CHAP secrets in tfvars.
install_gitops              = true
enable_layer_netapp_storage = true

# Preserve an existing system's generation. This Gen1 example is cost-conscious,
# not a production sizing recommendation. SSD is billed for provisioned capacity.
fsx_deployment_type          = "SINGLE_AZ_1"
fsx_storage_capacity_gb      = 1024
fsx_throughput_capacity_mbps = 128
fsx_create_dedicated_subnets = false

netapp_operator_config = {
  install_plan_approval = "Manual"
  # Approve a maintenance window: this may roll/reboot workers.
  node_prep_iscsi = true
  # Enable only after measuring a control-plane provisioning backlog:
  enable_concurrency = false
}
netapp_storage_config = {
  san_enabled         = true
  use_chap            = true
  backend_secret_name = "trident-svm-credentials" # Delivered separately in trident
  management_endpoint = "svm.example.internal"    # Must match the trusted certificate
  trusted_ca_pem      = ""                        # REQUIRED: replace with approved PEM contents
  # Existing installs only: retain immutable old classes until PVC migration.
  legacy_classes_enabled = false
}
netapp_fsx_config = {
  automatic_backup_retention_days = 7
  # Empty client CIDRs use the ROSA worker subnet CIDRs.
  # For BYO-VPC Multi-AZ, supply every client route table:
  # client_route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef1"]
}

# New production deployment OPTION after regional/quota/cost checks:
# fsx_deployment_type          = "MULTI_AZ_2"
# fsx_throughput_capacity_mbps = 768
# fsx_storage_capacity_gb      = 2048
# Do not use these overrides to replace an existing filesystem.
# Choose new retained classes explicitly:
# fsx-ontap-nfs-retain, fsx-ontap-san-retain, fsx-ontap-vm-rwx.
