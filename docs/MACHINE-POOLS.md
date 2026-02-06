# Machine Pools Guide

This guide covers creating and managing additional machine pools for ROSA clusters. Machine pools allow you to run specialized workloads on dedicated node types with specific configurations.

## Overview

Machine pools are configured using a generic list in your `tfvars` file. Each pool is defined as an object with properties for instance type, scaling, labels, taints, and more.

```hcl
machine_pools = [
  {
    name          = "pool-name"
    instance_type = "m5.xlarge"
    replicas      = 2
    # ... additional configuration
  }
]
```

## Platform Differences

### HCP vs Classic

| Feature | HCP | Classic |
|---------|-----|---------|
| Spot Instances | Coming soon | Supported |
| Version Control | Must be within n-2 of control plane | Matches cluster |
| Multi-AZ | Single subnet per pool | Configurable |
| Disk Size | Fixed | Configurable |

### Version Constraints (HCP Only)

HCP machine pools must be within **n-2** of the control plane version:

```
Control Plane: 4.18.x
Valid Pool Versions: 4.18.x, 4.17.x, 4.16.x
Invalid: 4.15.x and below
```

**Upgrade Order:** Always upgrade control plane first, then machine pools.

Use `machine_pool_version` in tfvars to manage upgrades:

```hcl
openshift_version     = "4.18.5"   # Control plane
machine_pool_version  = "4.17.10"  # Machine pools (upgrade separately)
```

## Pool Configuration Reference

### Common Properties (Both HCP and Classic)

```hcl
{
  name          = string           # Required: Pool name
  instance_type = string           # Required: EC2 instance type
  replicas      = number           # Optional: Fixed count (default: 2)
  autoscaling   = {                # Optional: Auto-scaling config
    enabled = bool
    min     = number
    max     = number
  }
  labels        = map(string)      # Optional: Node labels
  taints        = list(object)     # Optional: Node taints
  subnet_id     = string           # Optional: Override default subnet
}
```

### HCP-Only Properties

```hcl
{
  attach_ecr_policy = bool         # Attach ECR readonly policy to pool (default: false)
}
```

**Note:** HCP machine pools each get their own `instance_profile` computed by ROSA. The `attach_ecr_policy` option attaches `AmazonEC2ContainerRegistryReadOnly` to that pool's instance profile, enabling workers in that pool to pull from ECR.

### Classic-Only Properties

```hcl
{
  spot = {                         # Spot instance config (up to 90% savings)
    enabled   = bool
    max_price = string             # Optional: Max hourly price
  }
  disk_size         = number       # Root disk size in GB (default: 300)
  multi_az          = bool         # Distribute across AZs (default: true)
  availability_zone = string       # Specific AZ (if multi_az = false)
}
```

## Pool Examples

### GPU Pool (NVIDIA)

For ML/AI workloads requiring GPU acceleration.

```hcl
{
  name          = "gpu"
  instance_type = "g4dn.xlarge"    # Or p3.2xlarge, p4d.24xlarge
  replicas      = 2
  labels = {
    "node-role.kubernetes.io/gpu"    = ""
    "nvidia.com/gpu.workload.config" = "container"
  }
  taints = [{
    key           = "nvidia.com/gpu"
    value         = "true"
    schedule_type = "NoSchedule"
  }]
}
```

**Workload targeting:**
```yaml
nodeSelector:
  node-role.kubernetes.io/gpu: ""
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

**GovCloud GPU instances:** `p3.2xlarge`, `p3.8xlarge`, `g4dn.xlarge` (verify availability)

### GPU Spot Pool (Classic Only)

Cost-effective GPU computing for batch/training workloads that can tolerate interruptions.

```hcl
{
  name          = "gpu-spot"
  instance_type = "g4dn.xlarge"
  spot          = { enabled = true, max_price = "0.50" }
  autoscaling   = { enabled = true, min = 0, max = 4 }
  multi_az      = false            # Spot capacity varies by AZ
  labels = {
    "node-role.kubernetes.io/gpu" = ""
    "spot"                        = "true"
  }
  taints = [
    { key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" },
    { key = "spot", value = "true", schedule_type = "PreferNoSchedule" }
  ]
}
```

**Benefits:**
- Up to 90% cost savings vs on-demand
- Scale to 0 when idle
- Automatic node replacement on interruption

**Considerations:**
- 2-minute interruption warning
- Not for stateful or long-running critical workloads
- Use PodDisruptionBudgets for graceful handling

### Bare Metal Pool (OpenShift Virtualization)

Required for running VMs using OpenShift Virtualization (KubeVirt).

```hcl
{
  name          = "metal"
  instance_type = "m5.metal"       # Or c5.metal, m5zn.metal
  replicas      = 3                # Minimum 3 for production
  labels = {
    "node-role.kubernetes.io/metal" = ""
  }
  taints = [{
    key           = "node-role.kubernetes.io/metal"
    value         = "true"
    schedule_type = "NoSchedule"
  }]
}
```

**Integration with Virtualization Layer:**

When using `enable_layer_virtualization = true`, ensure you have a bare metal pool configured.

**Available bare metal instances:**
- `m5.metal` - General purpose (96 vCPU, 384 GB RAM)
- `c5.metal` - Compute optimized (96 vCPU, 192 GB RAM)
- `m5zn.metal` - High frequency (48 vCPU, 192 GB RAM)
- `r5.metal` - Memory optimized (96 vCPU, 768 GB RAM)

### ARM/Graviton Pool

Cost-optimized pool using AWS Graviton processors (ARM64 architecture).

```hcl
{
  name          = "graviton"
  instance_type = "m6g.xlarge"     # Graviton2
  # instance_type = "m7g.xlarge"   # Graviton3 (higher performance)
  autoscaling   = { enabled = true, min = 2, max = 10 }
  labels = {
    "kubernetes.io/arch" = "arm64"
  }
}
```

**Benefits:**
- Up to 40% cost savings vs x86
- Better price/performance for many workloads
- Lower energy consumption

**Workload targeting:**
```yaml
nodeSelector:
  kubernetes.io/arch: arm64
```

**Considerations:**
- Application must be built for ARM64
- Not all container images support ARM
- Test thoroughly before production deployment

**GovCloud:** Check Graviton availability in your region.

### High Memory Pool

For memory-intensive workloads like databases, caching, and analytics.

```hcl
{
  name          = "highmem"
  instance_type = "r5.2xlarge"     # Or r6i.2xlarge, x2idn.xlarge
  autoscaling   = { enabled = true, min = 2, max = 8 }
  labels = {
    "node-role.kubernetes.io/highmem" = ""
  }
}
```

**Memory-optimized instances:**
- `r5.xlarge` - 32 GB RAM, 4 vCPU
- `r5.2xlarge` - 64 GB RAM, 8 vCPU
- `r5.4xlarge` - 128 GB RAM, 16 vCPU
- `x2idn.xlarge` - 128 GB RAM, 4 vCPU (highest memory/CPU ratio)

### General Worker Pool with Autoscaling

Additional capacity with automatic scaling based on demand.

```hcl
{
  name          = "workers"
  instance_type = "m5.xlarge"
  autoscaling   = { enabled = true, min = 2, max = 10 }
}
```

## Labels and Taints

### Common Labels

| Label | Purpose |
|-------|---------|
| `node-role.kubernetes.io/gpu` | GPU workloads |
| `node-role.kubernetes.io/metal` | Bare metal / virtualization |
| `node-role.kubernetes.io/highmem` | Memory-intensive workloads |
| `kubernetes.io/arch` | CPU architecture (arm64, amd64) |
| `spot` | Spot/preemptible instances |

### Taint Schedule Types

| Type | Effect |
|------|--------|
| `NoSchedule` | Pods won't be scheduled without toleration |
| `PreferNoSchedule` | Scheduler avoids but may still schedule |
| `NoExecute` | Evicts existing pods without toleration |

### Example: Dedicated Pool with Taint

```hcl
{
  name = "dedicated-team-a"
  instance_type = "m5.xlarge"
  replicas = 3
  labels = {
    "team" = "team-a"
  }
  taints = [{
    key           = "team"
    value         = "team-a"
    schedule_type = "NoSchedule"
  }]
}
```

Pod targeting:
```yaml
nodeSelector:
  team: team-a
tolerations:
  - key: "team"
    operator: "Equal"
    value: "team-a"
    effect: "NoSchedule"
```

## Best Practices

### Production Recommendations

1. **Use autoscaling** - Set appropriate min/max for resilience
2. **Multi-AZ** (Classic) - Distribute across AZs for HA
3. **Right-size instances** - Match instance type to workload needs
4. **Label strategically** - Use consistent labeling conventions
5. **Test taints** - Verify pods can schedule before production

### Cost Optimization

1. **Spot instances** (Classic) - Use for fault-tolerant batch workloads
2. **Graviton** - Consider ARM for compatible workloads
3. **Scale to zero** - Set `min = 0` for specialized pools
4. **Right-size** - Avoid over-provisioning instance types

### GovCloud Considerations

- Verify instance type availability in your GovCloud region
- GPU instances may have limited availability
- Graviton availability varies by region
- Some instance families may not be available

## Troubleshooting

### Pool Not Creating

1. Check instance type availability in your region
2. Verify subnet has available IPs
3. Check IAM permissions for node creation
4. Review cluster autoscaler logs if using autoscaling

### Pods Not Scheduling

1. Verify node labels match pod nodeSelector
2. Check tolerations match taints exactly
3. Ensure sufficient resources (CPU/memory)
4. Check for conflicting affinity rules

### Autoscaling Not Working

1. Verify autoscaler is enabled on cluster
2. Check min/max settings are appropriate
3. Review autoscaler logs for errors
4. Ensure pods have resource requests defined

## Related Documentation

- [Operations Guide](./OPERATIONS.md)
- [Observability Guide](./OBSERVABILITY.md)
- [Zero-Egress Guide](./ZERO-EGRESS.md)
- [Virtualization Example](../examples/ocpvirtualization.tfvars)
- [Observability Example](../examples/observability.tfvars)
