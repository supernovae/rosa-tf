# ROSA HCP IAM Roles Module

Creates IAM roles and OIDC configuration for ROSA with Hosted Control Planes.

## Overview

HCP uses **AWS-managed policies** instead of customer-managed policies. This simplifies management and ensures policies are automatically updated by AWS.

## Key Differences from Classic

| Component | HCP | Classic |
|-----------|-----|---------|
| Account Roles | 3 (no ControlPlane) | 4 |
| Operator Roles | 8 | 6-7 |
| Policy Management | AWS-managed | Customer-managed |
| OIDC Config | Managed | Manual |

## Account Roles (3)

| Role | Purpose |
|------|---------|
| Installer | Cluster installation |
| Worker | EC2 worker node operations |
| Support | Red Hat SRE access |

Note: HCP does not have a ControlPlane role because the control plane runs in Red Hat's account.

## Operator Roles (8)

| Role | Namespace | Service Account |
|------|-----------|-----------------|
| EBS CSI Driver | openshift-cluster-csi-drivers | aws-ebs-csi-driver-controller-sa |
| Cloud Network | openshift-cloud-network-config-controller | cloud-network-config-controller |
| Machine API | openshift-machine-api | machine-api-controllers |
| Image Registry | openshift-image-registry | installer-cloud-credentials |
| Ingress | openshift-ingress-operator | ingress-operator |
| Kube Controller | kube-system | kube-controller-manager |
| Control Plane Operator | kube-system | control-plane-operator |
| KMS Provider | kube-system | kms-provider |

## AWS Managed Policies

HCP uses these AWS-managed policies (maintained by AWS):

| Policy | Description |
|--------|-------------|
| ROSAInstallerPolicy | Cluster installation |
| ROSAWorkerInstancePolicy | Worker node operations |
| ROSASRESupportPolicy | Red Hat SRE support |
| ROSAAmazonEBSCSIDriverOperatorPolicy | EBS CSI operations |
| ROSAIngressOperatorPolicy | Load balancer management |
| ROSAImageRegistryOperatorPolicy | Image registry S3 |
| ROSACloudNetworkConfigOperatorPolicy | VPC networking |
| ROSAKubeControllerPolicy | Kubernetes controller |
| ROSANodePoolManagementPolicy | Machine pool management |
| ROSAKMSProviderPolicy | KMS encryption |
| ROSAControlPlaneOperatorPolicy | Control plane operations |

See [AWS Documentation](https://docs.aws.amazon.com/rosa/latest/userguide/security-iam-awsmanpol.html) for policy details.

## Policy Architecture

This module follows the official [terraform-rhcs-rosa-hcp](https://github.com/terraform-redhat/terraform-rhcs-rosa-hcp) approach:

### How Policies Are Attached

```
aws_iam_role_policy_attachment  →  AWS managed policy ARN
                                    (e.g., arn:aws:iam::aws:policy/service-role/ROSAInstallerPolicy)
```

**Not inline policies** - We use `aws_iam_role_policy_attachment` to attach pre-existing AWS managed policies.

### Key Differences from Classic

| Aspect | HCP | Classic |
|--------|-----|---------|
| Policy Source | AWS managed service-role policies | `data.rhcs_policies.operator_role_policies` |
| Policy Creation | Not needed (AWS manages) | Customer creates managed policies |
| Policy Attachment | `aws_iam_role_policy_attachment` | `aws_iam_role_policy_attachment` |
| Policy Updates | Automatic by AWS | Update RHCS provider |

### Why This Approach?

1. **AWS Manages Policies**: HCP policies are AWS service-role policies maintained by AWS
2. **No Hardcoded Policy Documents**: We reference ARNs, not embedded JSON
3. **Automatic Updates**: AWS updates policies as ROSA evolves
4. **Consistent with ROSA CLI**: Same policies as `rosa create operator-roles`

## ECR and KMS Architecture

### ECR Policy (Per-Machine-Pool)

ECR access is **NOT managed at the account role level** for HCP. Instead:

1. Each machine pool gets its own `instance_profile` (computed by ROSA)
2. ECR policy should be attached per-pool using `attach_ecr_policy = true`
3. This allows granular control over which pools can pull from ECR

```hcl
# In machine pools configuration
machine_pools = [
  {
    name              = "app-pool"
    instance_type     = "m5.xlarge"
    replicas          = 2
    attach_ecr_policy = true  # Attach ECR policy to this pool only
  }
]
```

See `modules/cluster/machine-pools-hcp` for per-pool ECR attachment.

### KMS Policy (Via Key Policy)

KMS access is **NOT managed via IAM role policies** for HCP. Instead:

1. Pass `kms_key_arn` to the cluster resource
2. RHCS handles the integration automatically
3. Your KMS key policy must grant access to operator roles

**KMS Key Policy Requirements:**

```json
{
  "Sid": "ROSA KMS Provider Permissions",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT:role/PREFIX-kube-system-kms-provider"
  },
  "Action": ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"],
  "Resource": "*"
}
```

See [Red Hat KMS Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-creating-cluster-with-aws-kms-key) for the complete key policy.

### Differences from Classic

| Aspect | HCP | Classic |
|--------|-----|---------|
| ECR Policy | Per-machine-pool instance profile | Account-level Worker role |
| KMS Policy | KMS key policy (on the key) | IAM role policy (on roles) |
| Why Different? | HCP pools get unique instance profiles | Classic shares Worker role |

## Usage

```hcl
module "iam_roles" {
  source = "../../modules/security/iam/rosa-hcp"

  cluster_name         = "my-hcp-cluster"
  account_role_prefix  = "my-hcp-cluster"
  operator_role_prefix = "my-hcp-cluster"

  # Optional: External ID for support role
  support_role_external_id = var.support_external_id

  tags = {
    Environment = "prod"
  }
}
```

## GovCloud Support

The module automatically detects AWS partition and uses correct ARNs:

```hcl
# Commercial
arn:aws:iam::aws:policy/ROSAInstallerPolicy

# GovCloud
arn:aws-us-gov:iam::aws:policy/ROSAInstallerPolicy
```

## Outputs

```hcl
# OIDC Configuration
output "oidc_config_id"      # For cluster creation
output "oidc_endpoint_url"   # For IRSA setup
output "oidc_provider_arn"   # For trust policies

# Account Roles
output "installer_role_arn"  # For cluster creation
output "worker_role_arn"     # For worker nodes
output "support_role_arn"    # For Red Hat SRE

# Operator Roles
output "operator_role_arns"  # Map of all operator role ARNs
```

## IAM Propagation

The module includes a 30-second wait after role creation to ensure IAM propagation before cluster creation.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.4.6 |
| aws | >= 5.0 |
| rhcs | >= 1.6.3 |
