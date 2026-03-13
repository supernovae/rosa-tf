# AutoNode IAM Module

> **Technology Preview -- Not for Production Use**
>
> AutoNode (Karpenter) on ROSA HCP is a Technology Preview feature. Technology Preview features are not fully supported under Red Hat subscription service level agreements, may not be functionally complete, and are not intended for production use. Clusters with AutoNode enabled should be treated as disposable test environments.
>
> See: https://access.redhat.com/support/offerings/techpreview

Creates the AWS IAM resources and subnet tags required for Karpenter on ROSA HCP.

## What This Module Creates

1. **Karpenter controller IAM policy** -- EC2, IAM, SSM, SQS, and Pricing permissions
2. **Karpenter IAM role** -- OIDC trust policy scoped to `kube-system:karpenter` service account
3. **Control-plane-operator inline policy** -- `ec2:CreateTags` on the existing control-plane-operator role
4. **Subnet discovery tags** -- `karpenter.sh/discovery = <cluster_id>` on private subnets
5. **ECR pull policy** (optional) -- attaches `AmazonEC2ContainerRegistryReadOnly` to the Karpenter role

## Usage

```hcl
module "autonode" {
  source = "../../modules/cluster/autonode"
  count  = var.enable_autonode ? 1 : 0

  cluster_name         = var.cluster_name
  cluster_id           = module.rosa_cluster.cluster_id
  oidc_endpoint_url    = module.iam_roles.oidc_endpoint_url
  operator_role_prefix = var.cluster_name
  private_subnet_ids   = local.effective_private_subnet_ids
  enable_ecr_pull      = var.create_ecr && var.enable_autonode

  tags = local.common_tags

  depends_on = [module.rosa_cluster]
}
```

After `terraform apply`, enable AutoNode manually:

```bash
terraform output -raw rosa_enable_autonode_command | bash
```

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `cluster_name` | string | yes | | ROSA HCP cluster name |
| `cluster_id` | string | yes | | OCM cluster ID (used for subnet discovery tags) |
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
| `rosa_enable_command` | CLI command to enable AutoNode on the cluster |
| `tagged_subnet_ids` | Subnet IDs tagged with Karpenter discovery tags |

## See Also

- [docs/AUTONODE.md](../../../docs/AUTONODE.md) -- full deployment guide and known limitations
- [modules/cluster/autonode-pool/](../autonode-pool/) -- companion module for NodePool CRDs
