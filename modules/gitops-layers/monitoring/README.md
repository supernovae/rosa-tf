# AWS resources for observability

Creates the Loki S3 bucket, OIDC IAM role and bucket-scoped S3/optional KMS policy.
Kubernetes deployment is managed by the sibling operator module. See the
[operations guide](../../../docs/OBSERVABILITY.md) and
[AWS recovery runbooks](../../../docs/OBSERVABILITY-AWS-RECOVERY.md).

The bucket is CloudFormation-owned, encrypted, versioned, public-access-blocked
and TLS-only. `DeletionPolicy` and `UpdateReplacePolicy` retain it after stack
deletion/replacement. Destruction still removes IAM resources; retained data alone
is not a working recovery service. Do not add a competing Terraform bucket owner.

~~~hcl
module "monitoring" {
  source            = "../../modules/gitops-layers/monitoring"
  cluster_name      = var.cluster_name
  oidc_endpoint_url = module.iam_roles.oidc_endpoint_url
  aws_region        = var.aws_region
  log_retention_days = 30
  # kms_key_arn = module.kms.infra_kms_key_arn
  tags = local.common_tags
}
~~~

| Input | Default | Purpose |
| --- | --- | --- |
| `cluster_name`, `oidc_endpoint_url`, `aws_region` | Required | Identity and regional resources; OIDC URL without https:// |
| `s3_bucket_name` | Generated | `{cluster_name}-{random_8hex}-loki-logs`, length constrained |
| `log_retention_days` | 30 | Noncurrent object version retention (1–365 days); parent also configures Loki compactor |
| `kms_key_arn` | null | Customer KMS key, otherwise SSE-S3 |
| `iam_role_path` | `/` | IAM role path |
| `tags` | `{}` | Resource tags |
| `is_govcloud`, `openshift_version` | false, `4.20` | Compatibility inputs; partition is discovered, APIs are selected elsewhere |

Only Loki's compactor expires current chunks and indexes. Independent S3 current
object expiry can break queries. Lifecycle rules abort incomplete uploads after
seven days, expire noncurrent versions and clean expired delete markers. Versioning
extends physical lifetime beyond query retention; this is neither immutable audit
retention nor a complete backup. Do not transition the live store to Glacier.

The trust policy restricts both service-account subject and `sts.amazonaws.com`
audience. Loki uses short-lived web identity, not static S3 keys. GovCloud ARNs
use the detected AWS partition. Zero-egress deployments still need regional S3/STS
connectivity and endpoint policies allowing the bucket and role.

Outputs include `loki_bucket_name`, `loki_bucket_arn`, `loki_bucket_region`,
`loki_role_arn`, `loki_role_name`, `s3_endpoint`, `logging_namespace`, retention and
`gitops_config`. Protect KMS keys and record these dependencies in recovery plans.

Do not use `aws s3 rb --force` as a versioned-bucket cleanup procedure: it does not
remove every version/delete marker. After retention/legal-hold approval, inventory
all versions and delete markers using a reviewed, paginated cleanup procedure.
No cleanup is automatic. Retained buckets continue incurring charges.
