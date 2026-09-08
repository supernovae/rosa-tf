# Preserve existing logins and admin grants when adopting native bootstrap.
removed {
  from = rhcs_identity_provider.htpasswd
  lifecycle {
    destroy = false
  }
}

removed {
  from = rhcs_group_membership.cluster_admin
  lifecycle {
    destroy = false
  }
}
