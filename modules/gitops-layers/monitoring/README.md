# Monitoring Resources Module

This Terraform module creates the AWS resources required for the OpenShift Monitoring and Logging layer.

## Overview

The module provisions:

| Resource | Purpose |
|----------|---------|
| **S3 Bucket** | Loki log storage with versioning and encryption |
| **IAM Role** | STS-enabled role for Loki service accounts |
| **IAM Policy** | S3 read/write and optional KMS permissions |

## Usage

```hcl
module "monitoring" {
  source = "../../modules/gitops-layers/monitoring"

  cluster_name      = var.cluster_name
  oidc_endpoint_url = module.iam_roles.oidc_endpoint_url
  aws_region        = var.aws_region

  # Retention (default: 30 days)
  log_retention_days = 30

  # Optional: Custom bucket name
  # s3_bucket_name = "my-custom-loki-bucket"

  # Optional: KMS encryption
  # kms_key_arn = module.kms.infra_kms_key_arn

  # Environment detection
  is_govcloud       = false
  openshift_version = "4.20"

  tags = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `cluster_name` | Name of the ROSA cluster | `string` | - | yes |
| `oidc_endpoint_url` | OIDC provider endpoint URL (without https://) | `string` | - | yes |
| `aws_region` | AWS region for S3 bucket | `string` | - | yes |
| `s3_bucket_name` | Custom S3 bucket name (see [Bucket Naming](#s3-bucket-naming)) | `string` | `""` | no |
| `log_retention_days` | Log retention in days (1-365) | `number` | `30` | no |
| `kms_key_arn` | KMS key ARN for S3 encryption | `string` | `null` | no |
| `iam_role_path` | IAM role path | `string` | `"/"` | no |
| `is_govcloud` | Whether this is a GovCloud deployment | `bool` | `false` | no |
| `openshift_version` | OpenShift version for API compatibility | `string` | `"4.20"` | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |

> **Note:** S3 buckets are NOT deleted on `terraform destroy` to prevent accidental data loss.
> After destroying the cluster, manually clean up: `aws s3 rb s3://BUCKET_NAME --force`

## Outputs

| Name | Description |
|------|-------------|
| `loki_bucket_name` | Name of the S3 bucket for Loki |
| `loki_bucket_arn` | ARN of the S3 bucket |
| `loki_bucket_region` | Region of the S3 bucket |
| `loki_role_arn` | ARN of the IAM role for Loki |
| `loki_role_name` | Name of the IAM role |
| `s3_endpoint` | S3 endpoint URL for Loki configuration |
| `logging_namespace` | Namespace for logging components |
| `log_retention_days` | Configured retention in days |
| `log_retention_hours` | Configured retention in hours |
| `gitops_config` | Configuration map for GitOps layer |

## S3 Bucket Naming

S3 bucket names must be:
- **Globally unique** across all AWS accounts worldwide
- **DNS compliant**: 3-63 characters, lowercase letters, numbers, and hyphens only

### Default Naming Pattern

```
{cluster_name}-{random_8hex}-loki-logs
```

The module automatically:
- Generates a random 8-character hex suffix for global uniqueness
- Truncates cluster name to fit within the 63-character S3 limit
- Converts to lowercase and replaces underscores with hyphens

**Example**: For cluster `my-rosa-prod`:
```
my-rosa-prod-a3f7b2c1-loki-logs
```

### S3 Bucket Lifecycle

The S3 bucket is created via CloudFormation with `DeletionPolicy: Retain`. On
`terraform destroy`, the bucket is **retained** (not deleted) to protect log data.
During destroy, Terraform prints cleanup commands for the retained bucket.

### Why Use a Random Suffix?

Without the account ID, generic names like `rosa-dev-loki-logs` will fail if:
- Another AWS account (anywhere in the world) already owns that bucket name
- You previously created a bucket with that name in a different region

The error typically looks like:
```
api error AuthorizationHeaderMalformed: The authorization header is malformed; 
the region 'us-east-1' is wrong; expecting 'eu-central-1'
```

### Custom Bucket Name

To use a custom name instead, set `s3_bucket_name`:

```hcl
module "monitoring" {
  # ...
  s3_bucket_name = "my-org-rosa-logs-prod"
}
```

**Note**: Custom names must be 3-63 characters, DNS compliant, and globally unique.

## S3 Bucket Configuration

The S3 bucket is configured with:

- **Versioning**: Enabled for data protection
- **Encryption**: AES256 by default, KMS if `kms_key_arn` provided
- **Public Access**: Blocked (all four settings)
- **Lifecycle Rules**:
  - Abort incomplete multipart uploads after 7 days
  - Expire log chunks after `log_retention_days`
  - Expire index files after `log_retention_days`

## IAM Role Trust Policy

The IAM role trusts the following Loki service accounts via OIDC:

```
system:serviceaccount:openshift-logging:loki
system:serviceaccount:openshift-logging:logging-loki
system:serviceaccount:openshift-logging:loki-distributor
system:serviceaccount:openshift-logging:loki-ingester
system:serviceaccount:openshift-logging:loki-querier
system:serviceaccount:openshift-logging:loki-query-frontend
system:serviceaccount:openshift-logging:loki-compactor
system:serviceaccount:openshift-logging:loki-index-gateway
system:serviceaccount:openshift-logging:loki-ruler
```

## IAM Policy Permissions

The IAM policy grants:

```json
{
  "S3BucketAccess": [
    "s3:GetBucketLocation",
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads"
  ],
  "S3ObjectAccess": [
    "s3:AbortMultipartUpload",
    "s3:DeleteObject",
    "s3:GetObject",
    "s3:ListMultipartUploadParts",
    "s3:PutObject"
  ],
  "KMSAccess (if kms_key_arn provided)": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ]
}
```

## Integration with GitOps Layer

Pass the module outputs to the GitOps operator module:

```hcl
module "gitops" {
  source = "../../modules/gitops-layers/operator"

  # ... other variables ...

  enable_layer_monitoring    = true
  monitoring_bucket_name     = module.monitoring.loki_bucket_name
  monitoring_role_arn        = module.monitoring.loki_role_arn
  monitoring_retention_days  = module.monitoring.log_retention_days
}
```

## GovCloud Considerations

For GovCloud deployments:

1. Set `is_govcloud = true`
2. Set `openshift_version = "4.16"` (or actual version)
3. The module will:
   - Use GovCloud S3 endpoint format
   - Use `aws-us-gov` partition for IAM ARNs

## Cost Optimization

S3 costs scale with log volume and retention:

| Retention | Estimated Monthly Cost* |
|-----------|------------------------|
| 7 days | ~$5-20 |
| 30 days | ~$20-80 |
| 90 days | ~$60-240 |

*Estimates based on medium cluster (~50 pods) with default log levels.

To reduce costs:
- Decrease retention period
- Filter out verbose logs in ClusterLogForwarder
- Use S3 Intelligent-Tiering (manual configuration)
