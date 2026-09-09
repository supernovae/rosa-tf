# OADP AWS resources

This module supplies a retained, encrypted, versioned S3 bucket and STS role to
the operator layer. See [the OADP guide](../../../docs/OADP.md) for support,
migration, recovery and retention responsibilities.

Required inputs: `cluster_name`, `oidc_endpoint_url`. Optional: `kms_key_arn`
(null), `iam_role_path` (`/`) and `tags` (`{}`). There is no retention-days input
here; the parent/operator layer applies Velero TTL.

Outputs: `bucket_name`, `bucket_arn`, `bucket_region`, `role_arn`, `role_name`,
`gitops_config`, `ready`. Existing bucket/random suffix and CloudFormation logical
identity are preserved. Terraform prevents stack destruction; CloudFormation
retains the bucket. Decommissioning requires a recovery-preservation plan.

Public access and non-TLS requests are blocked. IAM restricts OIDC subject and
audience, object access to `velero/`, and optional KMS use to regional S3.
There are no native EC2 snapshot rights. Only abandoned multipart uploads expire;
backup chunks/noncurrent versions do not. Budget for retained-version costs.
