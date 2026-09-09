# ROSA Classic virtualization overlay, not a complete cluster configuration.
# Apply with an approved Classic cluster base; do not copy HCP-only IAM/auth inputs.
# 1. Provision cluster + bare-metal pools with install_gitops=false first.
# 2. Confirm platform/region/version/instance/storage support with Red Hat/NetApp.
# 3. Apply the layer phase after API access and operator catalogs are ready.
# See docs/VIRTUALIZATION.md. HCP/GovCloud support is NOT implied by module wiring.
# Example pool replaces the base machine_pools list: merge any existing pools.
machine_pools = [{
  name          = "virt"
  instance_type = "m6i.metal" # Check regional ROSA offerings and quotas before using.
  replicas      = 3           # Size for N+1 capacity; no automatic cost-saving scale-down.
  labels = {
    "node-role.kubernetes.io/virtualization" = ""
  }
  taints = [{
    key = "virtualization", value = "true", schedule_type = "NoSchedule"
  }]
}]

install_gitops              = true
enable_layer_virtualization = true
virt_node_selector = {
  "node-role.kubernetes.io/virtualization" = ""
  "kubernetes.io/arch"                     = "amd64"
}
virt_tolerations = [{
  key = "virtualization", value = "true", effect = "NoSchedule", operator = "Equal"
}]
virt_config = {
  platform_support_confirmed = false       # Set true only AFTER the support/preflight review.
  install_plan_approval      = "Automatic" # Red Hat recommendation; Manual needs an approval process.
  common_boot_images         = false       # Use approved internal images initially.
  netapp_storage_profiles    = true        # Only creates profiles if the NetApp layer is also enabled.
}

# NetApp: combine with examples/netappstorage.tfvars, then configure real CA,
# endpoint, independent filesystem/SVM credentials, SAN and node preparation.
# Those objects are whole-object Terraform overrides, not deep-merged overlays.
# VM disks use fsx-ontap-vm-rwx (RWX/Block); NFS uses fsx-ontap-nfs-retain.
# No claim that one backend always outperforms another: benchmark your workload.
# Choose the current entitled OpenShift release from the regional ROSA catalog
# in your base tfvars. Do not install a 4.22 operator onto a 4.18 cluster.
