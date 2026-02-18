#------------------------------------------------------------------------------
# ROSA - NetApp FSx ONTAP Storage Example
#
# Complete example enabling the NetApp Storage layer with Astra Trident.
# Creates FSx ONTAP filesystem, SVM, and configures Trident with:
#   - fsx-ontap-nfs-rwx:     NFS StorageClass for RWX workloads (Dev Spaces)
#   - fsx-ontap-iscsi-block: iSCSI StorageClass for block workloads (VMs, DBs)
#   - fsx-ontap-snapshots:   VolumeSnapshotClass for enterprise backups
#
# COPY this file to your environment's gitops tfvars and customize.
#
# Usage (two-phase):
#   Phase 1 - Cluster:
#     terraform apply -var-file="cluster-dev.tfvars"
#   Phase 2 - GitOps + Storage:
#     terraform apply -var-file="cluster-dev.tfvars" -var-file="gitops-dev.tfvars"
#
# IMPORTANT: Set fsx_admin_password via environment variable for security:
#   export TF_VAR_fsx_admin_password="YourSecurePassword123"
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# GitOps + Layer Enablement
#------------------------------------------------------------------------------

install_gitops               = true
enable_layer_terminal        = true
enable_layer_netapp_storage  = true

# Other layers (uncomment to enable):
# enable_layer_oadp           = false
# enable_layer_virtualization = false
# enable_layer_monitoring     = false
# enable_layer_certmanager    = false

#------------------------------------------------------------------------------
# FSx ONTAP Configuration
#------------------------------------------------------------------------------

# Deployment type: SINGLE_AZ_1 (dev) or MULTI_AZ_1 (production)
fsx_deployment_type = "SINGLE_AZ_1"

# Storage capacity (minimum 1024 GiB, thin provisioned)
fsx_storage_capacity_gb = 1024

# Throughput: 128 MBps is sufficient for dev, 256-512 for production
fsx_throughput_capacity_mbps = 128

# Subnet strategy:
#   false (default): Reuse ROSA private subnets (simpler, good for dev)
#   true:            Create dedicated /28 subnets (recommended for production)
fsx_create_dedicated_subnets = false

# SVM admin password -- set via environment variable:
#   export TF_VAR_fsx_admin_password="YourSecurePassword123"
# fsx_admin_password = "..." # DO NOT hardcode in tfvars

#------------------------------------------------------------------------------
# Trident Configuration
#------------------------------------------------------------------------------

# FIPS mode (recommended for GovCloud/FedRAMP)
# netapp_enable_fips = false

# Log level: info (default), debug, trace
# netapp_trident_log_level = "info"

# Custom image for air-gapped deployments:
# netapp_trident_image = "your-registry.example.com/trident:24.06"

#------------------------------------------------------------------------------
# Production Example (uncomment for production deployment)
#------------------------------------------------------------------------------
#
# fsx_deployment_type          = "MULTI_AZ_1"
# fsx_storage_capacity_gb      = 2048
# fsx_throughput_capacity_mbps = 512
# fsx_create_dedicated_subnets = true
# fsx_dedicated_subnet_cidrs   = ["10.0.15.0/28", "10.0.15.16/28"]
# netapp_enable_fips           = true
