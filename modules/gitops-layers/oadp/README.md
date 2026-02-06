# OADP Resources Module

This module creates the AWS resources required for OpenShift API for Data Protection (OADP).

## Overview

OADP provides backup and restore capabilities for OpenShift clusters using Velero. This module creates:

- **S3 Bucket**: Versioned, encrypted storage for backup data
- **IAM Role**: With OIDC trust for the OADP service accounts
- **IAM Policy**: S3 and EC2 permissions for Velero operations

## Usage

```hcl
module "oadp_resources" {
  source = "./modules/oadp-resources"

  cluster_name      = "my-cluster"
  oidc_endpoint_url = module.iam_roles.oidc_endpoint_url
  kms_key_arn       = module.kms.infrastructure_kms_key_arn

  backup_retention_days = 30
  
  tags = {
    Environment = "production"
  }
}
```

## Integration with GitOps

This module outputs configuration values for the GitOps ConfigMap bridge:

```hcl
# Pass to gitops module
module "gitops" {
  source = "./modules/gitops"
  
  enable_layer_oadp = true
  oadp_bucket_name  = module.oadp_resources.bucket_name
  oadp_role_arn     = module.oadp_resources.role_arn
}
```

## S3 Bucket Naming

S3 bucket names must be:
- **Globally unique** across all AWS accounts worldwide
- **DNS compliant**: 3-63 characters, lowercase letters, numbers, and hyphens only

### Default Naming Pattern

```
{cluster_name}-{account_id}-oadp-backups
```

The module automatically:
- Includes your AWS account ID for global uniqueness
- Truncates cluster name to 37 characters max (ensures total ≤ 63 chars)
- Converts to lowercase and replaces underscores with hyphens

**Example**: For cluster `rosa-prod` in account `123456789012`:
```
rosa-prod-123456789012-oadp-backups
```

This prevents errors when another account already owns a generic name.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the ROSA cluster | string | - | yes |
| oidc_endpoint_url | OIDC provider endpoint URL | string | - | yes |
| kms_key_arn | KMS key ARN for encryption | string | null | no |
| iam_role_path | Path for IAM role | string | "/" | no |
| backup_retention_days | Days to retain backups | number | 30 | no |
| tags | Tags for resources | map(string) | {} | no |

> **Note:** S3 buckets are NOT deleted on `terraform destroy` to prevent accidental data loss.
> After destroying the cluster, manually clean up: `aws s3 rb s3://BUCKET_NAME --force`

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | S3 bucket name |
| bucket_arn | S3 bucket ARN |
| bucket_region | AWS region of the bucket |
| role_arn | IAM role ARN |
| role_name | IAM role name |
| gitops_config | Values for GitOps ConfigMap |
| ready | Dependency marker (true when all resources created) |

## Security Considerations

1. **Bucket Versioning**: Enabled to protect against accidental deletion
2. **Encryption**: Uses KMS if provided, otherwise AES256
3. **Public Access**: Blocked at all levels
4. **IAM Trust**: Scoped to specific OADP service accounts

## Backup Retention

The `backup_retention_days` variable controls S3 lifecycle rules:

- Set to `0` to disable automatic deletion (manual cleanup required)
- Recommended: 30-90 days for regular backups
- Consider compliance requirements when setting retention
