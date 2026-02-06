# ROSA HCP Cluster Module

Creates a Red Hat OpenShift Service on AWS (ROSA) cluster with Hosted Control Planes.

## Overview

This module manages the ROSA HCP cluster resource using `rhcs_cluster_rosa_hcp`. The control plane runs in Red Hat's infrastructure, with only worker nodes in your AWS account.

## Key Features

- Hosted control plane (no control plane nodes in your account)
- ~15 minute cluster provisioning
- AWS PrivateLink connectivity to control plane
- Support for private and public clusters
- Optional etcd encryption with KMS

## Usage

```hcl
module "rosa_cluster" {
  source = "../../modules/cluster/rosa-hcp"

  cluster_name   = "my-hcp-cluster"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  # Network - HCP only needs private subnets
  private_subnet_ids = module.vpc.private_subnet_ids
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  machine_cidr       = "10.0.0.0/16"

  # IAM from rosa-hcp IAM module
  oidc_config_id       = module.iam_roles.oidc_config_id
  installer_role_arn   = module.iam_roles.installer_role_arn
  support_role_arn     = module.iam_roles.support_role_arn
  worker_role_arn      = module.iam_roles.worker_role_arn
  operator_role_prefix = "my-hcp-cluster"

  # OpenShift version
  openshift_version = "4.16.0"
  channel_group     = "stable"

  # Compute
  compute_machine_type = "m5.xlarge"
  replicas             = 3

  # Security
  private_cluster  = true
  etcd_encryption  = true
  etcd_kms_key_arn = module.kms.cluster_kms_key_arn
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.4.6 |
| rhcs | >= 1.6.3 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Cluster name (1-15 chars) | string | n/a | yes |
| aws_region | AWS region | string | n/a | yes |
| aws_account_id | AWS account ID | string | n/a | yes |
| private_subnet_ids | Private subnet IDs | list(string) | n/a | yes |
| availability_zones | Availability zones | list(string) | n/a | yes |
| oidc_config_id | OIDC config ID | string | n/a | yes |
| installer_role_arn | Installer role ARN | string | n/a | yes |
| support_role_arn | Support role ARN | string | n/a | yes |
| worker_role_arn | Worker role ARN | string | n/a | yes |
| operator_role_prefix | Operator role prefix | string | n/a | yes |
| openshift_version | OpenShift version | string | n/a | yes |
| channel_group | Update channel | string | "stable" | no |
| compute_machine_type | Instance type | string | "m5.xlarge" | no |
| replicas | Worker count | number | 2 | no |
| private_cluster | Private cluster | bool | false | no |
| etcd_encryption | Enable etcd encryption | bool | true | no |
| etcd_kms_key_arn | KMS key for etcd | string | "" | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | Cluster ID |
| cluster_name | Cluster name |
| api_url | API server URL |
| console_url | Console URL |
| domain | Cluster domain |
| openshift_version | Deployed version |
| version_info | Version compatibility info |

## Version Drift

HCP requires machine pools to be within **n-2** of control plane version:

```
Control Plane: 4.16.x
Allowed Pools: 4.16.x, 4.15.x, 4.14.x
```

The module includes a `check` block that warns about version compatibility. Set `skip_version_drift_check = true` to suppress during upgrades.

## Upgrade Procedure

1. Upgrade control plane first (update `openshift_version` in Terraform)
2. Verify control plane is healthy
3. Upgrade machine pools (can upgrade multiple concurrently)
4. Verify cluster health

> **Important**: Machine pools cannot use a newer version than the control plane.
> Always upgrade control plane before machine pools.

## Comparison with Classic

| Feature | HCP | Classic |
|---------|-----|---------|
| Control Plane | Red Hat managed (always multi-AZ) | Customer managed |
| Provisioning | ~15 min | ~40 min |
| Subnets Required | Private only | Private + Public |
| Account Roles | 3 | 4 |
| Operator Roles | 8 | 6-7 |
| Default Workers | 2 | 2 (single-AZ), 3 (multi-AZ) |
| Machine Pools | Single-AZ per pool | Multi-AZ per pool |

## Worker Scaling

The default worker count is **2**. HCP control plane is always multi-AZ (Red Hat managed), so VPC topology only affects NAT gateway costs, not worker requirements.

Each HCP machine pool targets a **single AZ** (one subnet). To distribute workloads across AZs:

```hcl
# Create pools across AZs for workload distribution
machine_pools = [
  { name = "workers-az-a", subnet_id = subnet_ids[0], replicas = 2 },
  { name = "workers-az-b", subnet_id = subnet_ids[1], replicas = 2 },
  { name = "workers-az-c", subnet_id = subnet_ids[2], replicas = 2 },
]
```

Scale workers based on workload needs, not VPC topology.
