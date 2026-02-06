# Additional Security Groups Module

Creates or aggregates additional security groups for ROSA clusters.

## Overview

ROSA clusters support attaching additional security groups to nodes for custom network access control. This module provides:

1. **Use existing security groups** - Pass pre-created security group IDs
2. **Create new security groups** - Define rules and let the module create them
3. **Intra-VPC template** - Quick-start with VPC-internal communication rules

> **IMPORTANT**: Security groups can only be attached at cluster **creation time**. They cannot be added or modified after the cluster is deployed.

## Supported Configurations

| Cluster Type | Compute | Control Plane | Infrastructure |
|--------------|---------|---------------|----------------|
| **HCP** | ✅ | ❌ (Red Hat managed) | ❌ (Red Hat managed) |
| **Classic** | ✅ | ✅ | ✅ |

## Usage

### Basic: Use Existing Security Groups

```hcl
module "additional_security_groups" {
  source = "../../modules/networking/security-groups"

  enabled      = true
  cluster_name = var.cluster_name
  cluster_type = "hcp"  # or "classic"
  vpc_id       = module.vpc.vpc_id

  # Attach existing security groups
  existing_compute_security_group_ids = ["sg-abc123", "sg-def456"]
}
```

### Intra-VPC Template

Creates security groups allowing all traffic within the VPC CIDR:

```hcl
module "additional_security_groups" {
  source = "../../modules/networking/security-groups"

  enabled                = true
  cluster_name           = var.cluster_name
  cluster_type           = "hcp"
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = var.vpc_cidr
  use_intra_vpc_template = true
}
```

> **WARNING**: The intra-VPC template creates permissive rules. For production, consider defining explicit rules instead.

### Custom Rules

```hcl
module "additional_security_groups" {
  source = "../../modules/networking/security-groups"

  enabled      = true
  cluster_name = var.cluster_name
  cluster_type = "classic"
  vpc_id       = module.vpc.vpc_id

  # Custom rules for compute nodes
  compute_ingress_rules = [
    {
      description = "Allow HTTPS from corporate network"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["10.100.0.0/16"]
    },
    {
      description = "Allow SSH from bastion"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.1.0/24"]
    }
  ]

  # Classic-only: control plane rules
  control_plane_ingress_rules = [
    {
      description = "Allow API access from corporate network"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = ["10.100.0.0/16"]
    }
  ]
}
```

### Combined: Existing + Custom

```hcl
module "additional_security_groups" {
  source = "../../modules/networking/security-groups"

  enabled      = true
  cluster_name = var.cluster_name
  cluster_type = "hcp"
  vpc_id       = module.vpc.vpc_id

  # Use existing security groups
  existing_compute_security_group_ids = ["sg-existing123"]

  # AND create additional custom rules
  compute_ingress_rules = [
    {
      description = "Custom rule for monitoring"
      from_port   = 9090
      to_port     = 9090
      protocol    = "tcp"
      cidr_blocks = ["10.200.0.0/16"]
    }
  ]
}
```

## Wiring to Cluster Module

Pass the outputs to your ROSA cluster module:

### HCP

```hcl
module "rosa_hcp_cluster" {
  source = "../../modules/cluster/rosa-hcp"
  # ... other variables ...

  aws_additional_compute_security_group_ids = module.additional_security_groups.compute_security_group_ids
}
```

### Classic

```hcl
module "rosa_classic_cluster" {
  source = "../../modules/cluster/rosa-classic"
  # ... other variables ...

  aws_additional_compute_security_group_ids       = module.additional_security_groups.compute_security_group_ids
  aws_additional_control_plane_security_group_ids = module.additional_security_groups.control_plane_security_group_ids
  aws_additional_infra_security_group_ids         = module.additional_security_groups.infra_security_group_ids
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `enabled` | Enable additional security groups | `bool` | `false` | no |
| `cluster_name` | ROSA cluster name | `string` | n/a | yes |
| `cluster_type` | Cluster type: `hcp` or `classic` | `string` | `"hcp"` | no |
| `vpc_id` | VPC ID | `string` | n/a | yes |
| `vpc_cidr` | VPC CIDR (required for intra-VPC template) | `string` | `""` | no |
| `use_intra_vpc_template` | Create intra-VPC permissive rules | `bool` | `false` | no |
| `existing_compute_security_group_ids` | Existing SG IDs for compute | `list(string)` | `[]` | no |
| `existing_control_plane_security_group_ids` | (Classic) Existing SG IDs for control plane | `list(string)` | `[]` | no |
| `existing_infra_security_group_ids` | (Classic) Existing SG IDs for infra | `list(string)` | `[]` | no |
| `compute_ingress_rules` | Custom ingress rules for compute | `list(object)` | `[]` | no |
| `compute_egress_rules` | Custom egress rules for compute | `list(object)` | `[]` | no |
| `control_plane_ingress_rules` | (Classic) Custom ingress rules for control plane | `list(object)` | `[]` | no |
| `control_plane_egress_rules` | (Classic) Custom egress rules for control plane | `list(object)` | `[]` | no |
| `infra_ingress_rules` | (Classic) Custom ingress rules for infra | `list(object)` | `[]` | no |
| `infra_egress_rules` | (Classic) Custom egress rules for infra | `list(object)` | `[]` | no |
| `tags` | Tags to apply | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `compute_security_group_ids` | Combined list of compute SG IDs |
| `control_plane_security_group_ids` | Combined list of control plane SG IDs (Classic only) |
| `infra_security_group_ids` | Combined list of infra SG IDs (Classic only) |
| `created_compute_sg_id` | ID of created compute SG (if any) |
| `created_control_plane_sg_id` | ID of created control plane SG (if any) |
| `created_infra_sg_id` | ID of created infra SG (if any) |
| `summary` | Summary of security group configuration |

## See Also

- [SECURITY-GROUPS.md](../../../docs/SECURITY-GROUPS.md) - Detailed guide and troubleshooting
