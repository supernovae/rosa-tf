# Overlay for any commercial/GovCloud Classic/HCP root.
# These optional keys preserve RHCS names; consult docs/RHCS-CAPABILITIES.md.
# Domain prefix is creation-time configuration: choose it before creating a cluster.
cluster_options = {
  domain_prefix   = "example-rosa"
  destroy_timeout = 120
  properties = {
    deployment_owner = "platform-team"
  }
}
