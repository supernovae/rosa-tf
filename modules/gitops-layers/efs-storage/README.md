# Regional EFS infrastructure

Creates encrypted regional EFS, worker-SG-only mount targets, automatic backups,
TLS/access-point-only filesystem access and a scoped STS controller role.
See [deployment and migration guidance](../../../docs/EFS-STORAGE.md).

Supply the cluster/VPC identity, one private subnet per worker AZ, OIDC issuer,
and `efs_config.allowed_security_group_ids`. Encryption is required. Defaults
are generalPurpose/elastic; a CMK is optional. Existing resource addresses and
filesystem identity are preserved. Terraform prevents filesystem destruction.
Neither a CSI snapshot service nor per-pod IAM mount authentication is provided.

The operator-facing filesystem ID output depends on mount targets, filesystem
policy and automatic backup configuration; role ARN depends on its policy
attachment. Do not replace those outputs with raw filesystem/role references.

Direct module callers should remove the obsolete `cluster_id`, `vpc_cidr` and
`is_govcloud` arguments. NFS authorization now uses worker SGs; partition/region
are derived from the configured AWS provider, not a boolean.
