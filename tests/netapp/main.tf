terraform {
  required_version = ">= 1.16.1, < 2.0.0"
}
locals {
  path    = "${path.module}/../../gitops-layers/layers/netapp-storage"
  release = yamldecode(file("${local.path}/release.yaml"))
  manifests = {
    subscription = yamldecode(templatefile("${local.path}/subscription.yaml.tftpl", {
      release = local.release, config = var.netapp_operator_config
    }))
    orchestrator = yamldecode(templatefile("${local.path}/trident-orchestrator.yaml.tftpl", {
      config = var.netapp_operator_config, log_level = "info", trident_image = ""
    }))
    nas = yamldecode(templatefile("${local.path}/backend-config-nas.yaml.tftpl", {
      management_endpoint = "svm.example.test", nfs_endpoint = "10.1.2.10", svm_name = "test-svm"
      backend_secret      = "approved-credentials", client_cidrs = ["10.1.0.0/24"], config = var.netapp_storage_config
    }))
    san = yamldecode(templatefile("${local.path}/backend-config-san.yaml.tftpl", {
      management_endpoint = "svm.example.test", svm_name = "test-svm"
      backend_secret      = "approved-credentials", config = var.netapp_storage_config
    }))
    nfs_class = yamldecode(templatefile("${local.path}/storageclass.yaml.tftpl", {
      name = "fsx-ontap-nfs-retain", protocol = "nfs", nconnect = var.netapp_storage_config.nfs_nconnect
    }))
    san_class = yamldecode(templatefile("${local.path}/storageclass.yaml.tftpl", {
      name = "fsx-ontap-san-retain", protocol = "san-filesystem", nconnect = 1
    }))
    vm_class = yamldecode(templatefile("${local.path}/storageclass.yaml.tftpl", {
      name = "fsx-ontap-vm-rwx", protocol = "san-block", nconnect = 1
    }))
    snapshot_class = yamldecode(file("${local.path}/snapshotclass-retain.yaml"))
  }
}
output "manifests" { value = local.manifests }
