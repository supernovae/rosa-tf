terraform {
  required_version = ">= 1.16.1, < 2.0.0"
}
variable "terraform_sa_namespace" { default = "rosa-terraform" }
variable "gitops_repo_url" { default = "https://git.example.com/team/workloads.git" }
variable "gitops_repo_revision" { default = "0123456789abcdef0123456789abcdef01234567" }
variable "openshift_minor" { default = "4.18" }
locals {
  path     = "${path.module}/../../gitops-layers/layers/gitops"
  channels = yamldecode(file("${local.path}/channels.yaml"))
  manifests = {
    argocd = yamldecode(templatefile("${local.path}/argocd.yaml.tftpl", { config = var.gitops_instance_config }))
    project = yamldecode(templatefile("${local.path}/project.yaml.tftpl", {
      namespace   = var.gitops_application.namespace, repo_url = var.gitops_repo_url
      view_groups = var.gitops_application.view_groups, sync_groups = var.gitops_application.sync_groups
    }))
    application = yamldecode(templatefile("${local.path}/application.yaml.tftpl", {
      config = var.gitops_application, repo_url = var.gitops_repo_url, revision = var.gitops_repo_revision, path = "apps"
    }))
    subscription = yamldecode(templatefile("${local.path}/subscription.yaml.tftpl", {
      config = var.gitops_operator_config, channel = local.channels[var.openshift_minor]
    }))
    default_project = yamldecode(file("${local.path}/default-project.yaml"))
  }
}
output "manifests" { value = local.manifests }
