# ROSA HCP Machine Pools Module

Manages machine pools for ROSA HCP clusters using `rhcs_hcp_machine_pool`.

## Overview

HCP machine pools differ from Classic:
- Use `rhcs_hcp_machine_pool` resource (not `rhcs_machine_pool`)
- Version must be within n-2 of control plane
- Single subnet per pool (not multi-AZ pool)
- No spot instance support in HCP (coming soon)
- Each pool gets its own `instance_profile` (computed by ROSA)

## Usage

### Generic Machine Pools List

The module uses a generic `machine_pools` list that supports any pool configuration:

```hcl
module "machine_pools" {
  source = "../../modules/cluster/machine-pools-hcp"

  cluster_id        = module.rosa_cluster.cluster_id
  openshift_version = "4.16.0"
  subnet_id         = module.vpc.private_subnet_ids[0]

  machine_pools = [
    {
      name          = "compute"
      instance_type = "m6i.xlarge"
      replicas      = 3
    },
    {
      name          = "gpu"
      instance_type = "g4dn.xlarge"
      replicas      = 2
      labels        = { "node-role.kubernetes.io/gpu" = "" }
      taints = [{
        key           = "nvidia.com/gpu"
        value         = "true"
        schedule_type = "NoSchedule"
      }]
    }
  ]
}
```

### ECR Policy Attachment

Each machine pool can optionally have ECR policy attached for pulling images from ECR:

```hcl
machine_pools = [
  {
    name              = "app-pool"
    instance_type     = "m6i.xlarge"
    replicas          = 2
    attach_ecr_policy = true  # Enables ECR access for this pool
  }
]
```

This attaches `AmazonEC2ContainerRegistryReadOnly` to the pool's instance profile.

### GPU Pool for ML/AI

```hcl
machine_pools = [
  {
    name          = "gpu-workers"
    instance_type = "g4dn.xlarge"  # NVIDIA T4
    replicas      = 2
    labels = {
      "node-role.kubernetes.io/gpu" = ""
    }
    taints = [{
      key           = "nvidia.com/gpu"
      value         = "true"
      schedule_type = "NoSchedule"
    }]
    autoscaling = {
      enabled = true
      min     = 0   # Scale to zero when idle
      max     = 4
    }
  }
]
```

### ARM/Graviton Pool for Cost Optimization

```hcl
machine_pools = [
  {
    name          = "graviton"
    instance_type = "m6g.xlarge"  # ARM-based
    replicas      = 2
    labels = {
      "kubernetes.io/arch" = "arm64"
    }
    autoscaling = {
      enabled = true
      min     = 1
      max     = 8
    }
  }
]
```

### High Memory Pool for Data Processing

```hcl
machine_pools = [
  {
    name          = "data-workers"
    instance_type = "r5.4xlarge"  # 128 GB RAM
    replicas      = 2
    labels = {
      "node-role.kubernetes.io/highmem" = ""
    }
    autoscaling = {
      enabled = true
      min     = 1
      max     = 4
    }
  }
]
```

### Mixed Workload Setup

```hcl
machine_pools = [
  # General compute with autoscaling
  {
    name          = "compute"
    instance_type = "m6i.2xlarge"
    labels        = { "workload-type" = "general" }
    autoscaling = {
      enabled = true
      min     = 2
      max     = 10
    }
  },
  # GPU for ML training
  {
    name          = "gpu"
    instance_type = "p3.2xlarge"  # NVIDIA V100
    labels        = { "node-role.kubernetes.io/gpu" = "" }
    taints = [{
      key           = "nvidia.com/gpu"
      value         = "true"
      schedule_type = "NoSchedule"
    }]
    autoscaling = {
      enabled = true
      min     = 0
      max     = 8
    }
  },
  # Memory for databases
  {
    name          = "highmem"
    instance_type = "r5.8xlarge"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/highmem" = "" }
  }
]
```

## Instance Types Reference

### GPU Instance Types

| Instance | GPU | Memory | Use Case |
|----------|-----|--------|----------|
| g4dn.xlarge | T4 | 16 GB | ML inference, lightweight training |
| g4dn.2xlarge | T4 | 32 GB | ML inference, medium workloads |
| g5.xlarge | A10G | 24 GB | ML training, graphics |
| p3.2xlarge | V100 | 16 GB | Deep learning training |
| p3.8xlarge | 4x V100 | 64 GB | Large model training |
| p4d.24xlarge | 8x A100 | 320 GB | Massive scale ML |

### High Memory Instance Types

| Instance | vCPU | Memory | Use Case |
|----------|------|--------|----------|
| r5.xlarge | 4 | 32 GB | Small databases |
| r5.2xlarge | 8 | 64 GB | Medium databases |
| r5.4xlarge | 16 | 128 GB | Large in-memory caches |
| r5.8xlarge | 32 | 256 GB | Data analytics |
| x2idn.xlarge | 4 | 128 GB | Memory-optimized |

### ARM/Graviton Instance Types

| Instance | vCPU | Memory | Use Case |
|----------|------|--------|----------|
| m6g.xlarge | 4 | 16 GB | General compute (cost-effective) |
| m6g.2xlarge | 8 | 32 GB | General compute |
| c6g.xlarge | 4 | 8 GB | Compute-optimized |
| r6g.xlarge | 4 | 32 GB | Memory-optimized |

## Version Drift

**Critical**: Machine pool version must be within n-2 of control plane.

```
Control Plane: 4.16.3
Pool Version: 4.16.3 ✓
Pool Version: 4.15.8 ✓
Pool Version: 4.14.12 ✓
Pool Version: 4.13.x  ✗ (too old)
```

**Upgrade Sequence**:
1. Upgrade control plane first (machine pools cannot exceed control plane version)
2. Wait for control plane to be healthy
3. Upgrade machine pools (can upgrade multiple concurrently)
4. Verify all pools are healthy

## Node Selectors and Tolerations

### GPU Workloads

```yaml
# Deployment targeting GPU nodes
spec:
  nodeSelector:
    node-role.kubernetes.io/gpu: ""
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
```

### High Memory Workloads

```yaml
# Deployment targeting high memory nodes
spec:
  nodeSelector:
    node-role.kubernetes.io/highmem: ""
```

### ARM/Graviton Workloads

```yaml
# Deployment targeting ARM nodes
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| cluster_id | HCP cluster ID | string | required |
| openshift_version | OpenShift version for pools | string | required |
| subnet_id | Default subnet ID for pools | string | required |
| machine_pools | List of machine pool configurations | list(object) | [] |
| auto_repair | Enable auto-repair for pools | bool | true |

### Machine Pool Object

Each pool in `machine_pools` supports:

| Field | Description | Required |
|-------|-------------|----------|
| name | Pool name | yes |
| instance_type | EC2 instance type | yes |
| replicas | Fixed replica count (ignored if autoscaling enabled) | no (default: 2) |
| autoscaling | `{ enabled, min, max }` | no |
| labels | Map of node labels | no |
| taints | List of `{ key, value, schedule_type }` | no |
| subnet_id | Override default subnet | no |
| attach_ecr_policy | Attach ECR readonly policy | no (default: false) |

## Outputs

| Name | Description |
|------|-------------|
| machine_pools | Map of pools with id, name, instance_type, instance_profile, status |
| pool_names | List of created pool names |
| pool_count | Number of pools created |
| pool_instance_profiles | Map of pool names to instance profiles |
