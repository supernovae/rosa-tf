terraform {
  required_version = ">= 1.16.1, < 2.0.0"
}

variable "region" { default = "us-east-1" }
variable "nameservers" { default = [] }
variable "recursive_only" { default = false }
variable "catalog_source" { default = "redhat-operators" }

locals {
  path = "${path.module}/../../gitops-layers/layers/certmanager"
  config = {
    channel               = "stable-v1"
    source                = var.catalog_source
    source_namespace      = "openshift-marketplace"
    install_plan_approval = "Automatic"
    controller_replicas   = 2
    webhook_replicas      = 3
    cainjector_replicas   = 2
  }
  issuers = { for name in ["cluster-issuer", "cluster-issuer-staging"] : name => yamldecode(templatefile("${local.path}/${name}.yaml.tftpl", {
    acme_email = "platform@example.com", hosted_zone_id = "Z0123456789ABCDEF", aws_region = var.region
  })) }
  certificate = yamldecode(templatefile("${local.path}/certificate.yaml.tftpl", {
    cert_name = "apps", cert_namespace = "openshift-ingress", cert_secret_name = "apps-tls", cert_domains = ["*.apps.example.com"], issuer_name = "letsencrypt-staging"
  }))
  subscription = yamldecode(templatefile("${local.path}/subscription.yaml.tftpl", { config = local.config }))
  controller = yamldecode(templatefile("${local.path}/controller-config.yaml.tftpl", {
    config = local.config, nameservers = var.nameservers, recursive_only = var.recursive_only
  }))
  manifests = merge(local.issuers, { certificate = local.certificate, subscription = local.subscription, controller = local.controller })
}

output "manifests" { value = local.manifests }
