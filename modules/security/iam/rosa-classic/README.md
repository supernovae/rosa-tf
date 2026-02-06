# IAM Roles Module - ROSA Classic

This module creates all IAM resources required for ROSA Classic clusters.

## Architecture

ROSA Classic uses **cluster-scoped IAM roles**:
- Each cluster has its own set of account and operator roles
- Roles are named using `cluster_name` as the default prefix
- Destroying a cluster cleanly removes its IAM roles
- No shared roles between clusters (unlike HCP which uses account-level roles)

## Resources Created

### Account Roles (4)

| Role | Purpose | Trust Principal |
|------|---------|-----------------|
| `<prefix>-Installer-Role` | Used during cluster installation | Red Hat Installer Role |
| `<prefix>-Support-Role` | Used by Red Hat SRE for support access | Red Hat SRE Role |
| `<prefix>-ControlPlane-Role` | Used by control plane nodes | EC2 Service |
| `<prefix>-Worker-Role` | Used by worker nodes | EC2 Service |

### OIDC Configuration

- OIDC configuration for STS authentication
- IAM OIDC provider for operator roles

### Operator Roles (6 commercial / 7 GovCloud)

| Operator | Namespace | Purpose |
|----------|-----------|---------|
| Cloud Network Config Controller | `openshift-cloud-network-config-controller` | Manages cloud network configuration |
| Machine API | `openshift-machine-api` | Node provisioning and management |
| Cloud Credential Operator | `openshift-cloud-credential-operator` | Manages cloud credentials (read-only) |
| Image Registry | `openshift-image-registry` | Image registry S3 storage |
| Ingress Operator | `openshift-ingress-operator` | Load balancers and DNS |
| Cluster CSI Drivers | `openshift-cluster-csi-drivers` | EBS CSI driver for volumes |
| **AWS VPC Endpoint Operator** | `openshift-aws-vpce-operator` | **GovCloud only** - VPC endpoint management |

## How Policies Are Managed

This module follows the official [terraform-rhcs-rosa-classic](https://github.com/terraform-redhat/terraform-rhcs-rosa-classic) approach:

1. **Policies from RHCS Provider**: All IAM policies come from `data.rhcs_policies.all_policies`
2. **No Hardcoded Policies**: We don't maintain policy documents in this module
3. **Managed Policies**: Operator policies are created as AWS managed policies (not inline)
4. **Policy Attachment**: Policies are attached to roles via `aws_iam_role_policy_attachment`

This ensures:
- Policies match what Red Hat expects and maintains
- Automatic updates when RHCS provider is updated
- Consistent behavior with `rosa create operator-roles` CLI

## Usage

```hcl
module "iam_roles" {
  source = "../../modules/security/iam/rosa-classic"

  cluster_name         = "my-cluster"
  openshift_version    = "4.16.50"
  
  # Optional: External operator role management
  # create_operator_roles = false
  
  tags = { Environment = "production" }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `cluster_name` | Name of the ROSA cluster | `string` | - | yes |
| `openshift_version` | OpenShift version (e.g., 4.16.50) | `string` | - | yes |
| `account_role_prefix` | Prefix for account IAM role names | `string` | `cluster_name` | no |
| `operator_role_prefix` | Prefix for operator IAM role names | `string` | `cluster_name` | no |
| `create_operator_roles` | Create operator roles via Terraform | `bool` | `true` | no |
| `path` | IAM path for roles and policies | `string` | `"/"` | no |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | no |

### OIDC Options

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_oidc_config` | Create a new OIDC configuration | `bool` | `true` |
| `managed_oidc` | Use Red Hat managed OIDC | `bool` | `true` |
| `oidc_config_id` | Existing OIDC config ID (when not creating) | `string` | `null` |
| `oidc_endpoint_url` | Existing OIDC endpoint (when not creating) | `string` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| `account_role_prefix` | Prefix used for account IAM roles |
| `operator_role_prefix` | Prefix used for operator IAM roles |
| `installer_role_arn` | ARN of the installer role |
| `support_role_arn` | ARN of the support role |
| `control_plane_role_arn` | ARN of the control plane role |
| `worker_role_arn` | ARN of the worker role |
| `oidc_config_id` | ID of the OIDC configuration |
| `oidc_endpoint_url` | OIDC endpoint URL |
| `operator_roles` | List of operator role ARNs |
| `operator_policies` | List of operator policy ARNs |

## Comparison with CLI

| Aspect | This Module | CLI (`rosa create`) |
|--------|-------------|---------------------|
| Account Roles | Created via Terraform | `rosa create account-roles` |
| Operator Roles | Created via Terraform | `rosa create operator-roles` |
| OIDC Config | Created via Terraform | `rosa create oidc-config` |
| Policy Source | `data.rhcs_policies` | Red Hat managed |
| Lifecycle | Tied to cluster | Separate management |

## External Role Management

If you prefer to manage operator roles via CLI:

```hcl
module "iam_roles" {
  source = "../../modules/security/iam/rosa-classic"

  cluster_name          = "my-cluster"
  openshift_version     = "4.16.50"
  create_operator_roles = false  # Skip operator role creation
}

# Then run:
# rosa create operator-roles --prefix my-cluster --oidc-config-id <id>
```

## See Also

- [docs/IAM-LIFECYCLE.md](../../../../docs/IAM-LIFECYCLE.md) - IAM architecture details
- [terraform-rhcs-rosa-classic](https://github.com/terraform-redhat/terraform-rhcs-rosa-classic) - Official module
