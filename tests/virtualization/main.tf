terraform { required_version = ">= 1.16.1, < 2.0.0" }
variable "ocp_minor" { default = 22 }
variable "node_selector" { default = { "node-role.kubernetes.io/virtualization" = "" } }
variable "tolerations" {
  default = [{ key = "virtualization", operator = "Equal", value = "true", effect = "NoSchedule" }]
}
locals {
  path = "${path.module}/../../gitops-layers/layers/virtualization"
  manifests = {
    subscription = yamldecode(templatefile("${local.path}/subscription.yaml.tftpl", {
      operator_channel = "stable", config = var.virt_config
    }))
    hco = yamldecode(templatefile("${local.path}/hyperconverged.yaml.tftpl", {
      node_selector = var.node_selector, tolerations = var.tolerations
      config        = var.virt_config, modern_boot_field = var.ocp_minor >= 19
    }))
    san = yamldecode(templatefile("${local.path}/storageprofile.yaml.tftpl", {
      storage_class = "fsx-ontap-vm-rwx", volume_mode = "Block"
    }))
    nfs = yamldecode(templatefile("${local.path}/storageprofile.yaml.tftpl", {
      storage_class = "fsx-ontap-nfs-retain", volume_mode = "Filesystem"
    }))
  }
}
output "manifests" { value = local.manifests }
