# AutoNode IAM Module

> AutoNode (Red Hat build of Karpenter) is GA and fully supported on ROSA HCP.
> Requires OpenShift 4.19+ and ROSA CLI >= 1.2.61.

Creates the AWS IAM resources and (optionally) subnet tags required for Karpenter on ROSA HCP.

## What This Module Creates

1. **Karpenter controller IAM policy** -- EC2, IAM, SSM, SQS, and Pricing permissions
2. **Karpenter IAM role** -- OIDC trust policy scoped to `kube-system:karpenter` service account
3. **Control-plane-operator inline policy** -- `ec2:CreateTags` on the existing control-plane-operator role
4. **Subnet discovery tags** -- `karpenter.sh/discovery = <cluster_id>` on private subnets (only when `cluster_id` is provided)
5. **ECR pull policy** (optional) -- attaches ECR read-only permissions to the Karpenter role

## Usage

### IAM-only mode (recommended)

Create the IAM role before the cluster, then pass `role_arn` to the cluster's `auto_node` block:

```hcl
module "autonode" {
  source = "../../modules/cluster/autonode"
  count  = var.enable_autonode ? 1 : 0

  cluster_name         = var.cluster_name
  cluster_id           = null  # IAM-only mode
  oidc_endpoint_url    = module.iam_roles.oidc_endpoint_url
  operator_role_prefix = var.cluster_name
  private_subnet_ids   = local.effective_private_subnet_ids
  enable_ecr_pull      = var.create_ecr && var.enable_autonode

  tags = local.common_tags
}

module "rosa_cluster" {
  # ...
  autonode_role_arn = var.enable_autonode ? module.autonode[0].karpenter_role_arn : null
}

# Subnet tags applied after cluster creation
resource "aws_ec2_tag" "karpenter_subnet_discovery" {
  for_each    = var.enable_autonode ? toset(local.effective_private_subnet_ids) : toset([])
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = module.rosa_cluster.cluster_id
}
```

AutoNode is enabled automatically via Terraform -- no manual CLI step required.

### Legacy mode (with cluster_id)

If `cluster_id` is provided, the module also applies subnet discovery tags:

```hcl
module "autonode" {
  source = "../../modules/cluster/autonode"
  count  = var.enable_autonode ? 1 : 0

  cluster_name         = var.cluster_name
  cluster_id           = module.rosa_cluster.cluster_id
  oidc_endpoint_url    = module.iam_roles.oidc_endpoint_url
  operator_role_prefix = var.cluster_name
  private_subnet_ids   = local.effective_private_subnet_ids

  tags = local.common_tags

  depends_on = [module.rosa_cluster]
}
```

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `cluster_name` | string | yes | | ROSA HCP cluster name |
| `cluster_id` | string | no | `null` | OCM cluster ID. When null, subnet tagging is skipped (IAM-only mode). |
| `oidc_endpoint_url` | string | yes | | OIDC endpoint URL (without `https://`) |
| `operator_role_prefix` | string | yes | | Prefix for ROSA operator IAM roles |
| `private_subnet_ids` | list(string) | yes | | Private subnet IDs to tag for Karpenter |
| `enable_ecr_pull` | bool | no | `false` | Attach ECR read-only policy to the Karpenter role |
| `tags` | map(string) | no | `{}` | Tags to apply to created resources |

## Outputs

| Name | Description |
|------|-------------|
| `karpenter_role_arn` | ARN of the Karpenter controller IAM role |
| `karpenter_policy_arn` | ARN of the Karpenter controller IAM policy |
| `rosa_enable_command` | DEPRECATED: empty string (AutoNode is now enabled via Terraform) |
| `tagged_subnet_ids` | Subnet IDs tagged with Karpenter discovery tags (empty in IAM-only mode) |

## See Also

- [docs/AUTONODE.md](../../../docs/AUTONODE.md) -- full deployment guide and known limitations
- [modules/cluster/autonode-pool/](../autonode-pool/) -- companion module for NodePool CRDs
