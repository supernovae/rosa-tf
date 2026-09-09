terraform { required_version = ">= 1.16.1, < 2.0.0" }
variable "role_arn" { default = "arn:aws:iam::123456789012:role/efs-csi" }
locals {
  path = "${path.module}/../../gitops-layers/layers/efs-storage"
  manifests = {
    subscription = yamldecode(templatefile("${local.path}/subscription.yaml.tftpl", {
      config = var.efs_config, role_arn = var.role_arn
    }))
    storageclass = yamldecode(templatefile("${local.path}/storageclass.yaml.tftpl", {
      efs_file_system_id = "fs-0123456789abcdef0", storage_class_name = "efs-rwx-retain"
    }))
    driver = yamldecode(file("${local.path}/cluster-csi-driver.yaml.tftpl"))
  }
}
output "manifests" { value = local.manifests }
