run "supported_defaults" {
  command = plan
  assert {
    condition     = local.subscription.spec.channel == "stable-v1" && local.controller.spec.webhookConfig.overrideReplicas == 3 && length(local.controller.spec.controllerConfig.overrideArgs) == 1
    error_message = "Follow the supported catalog, configure HA, and avoid forced public DNS resolvers."
  }
  assert {
    condition     = local.certificate.spec.privateKey.rotationPolicy == "Always" && local.certificate.spec.renewBeforePercentage == 33 && local.certificate.spec.revisionHistoryLimit == 1 && !can(local.certificate.spec.renewBefore)
    error_message = "Certificate rotation and relative renewal settings must be explicit."
  }
  assert {
    condition     = local.issuers["cluster-issuer"].spec.acme.solvers[0].dns01.route53.hostedZoneID == "Z0123456789ABCDEF" && !can(local.issuers["cluster-issuer"].spec.acme.solvers[0].dns01.route53.accessKeyID)
    error_message = "Use scoped zone IDs and ambient short-lived credentials, not static keys."
  }
}

run "govcloud_mirror_and_dns" {
  command = plan
  variables {
    region         = "us-gov-west-1"
    catalog_source = "approved-redhat-mirror"
    nameservers    = ["10.0.0.2:53"]
    recursive_only = true
  }
  assert {
    condition     = local.subscription.spec.source == "approved-redhat-mirror" && contains(local.controller.spec.controllerConfig.overrideArgs, "--dns01-recursive-nameservers=10.0.0.2:53") && contains(local.controller.spec.controllerConfig.overrideArgs, "--dns01-recursive-nameservers-only") && local.issuers["cluster-issuer"].spec.acme.solvers[0].dns01.route53.region == "us-gov-west-1"
    error_message = "Preserve GovCloud region, approved DNS and mirrored catalog settings."
  }
}
