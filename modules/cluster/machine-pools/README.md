# Machine Pools Module (Classic)

Creates additional machine pools for ROSA Classic clusters, enabling workload isolation, specialized compute (GPU, bare metal), and cost optimization through spot instances.

## Overview

ROSA clusters are created with a default worker machine pool. This module allows you to create additional pools for:

1. **Workload Isolation** - Separate pools for different teams, environments, or workload types
2. **Specialized Compute** - GPU instances for ML/AI, bare metal for virtualization
3. **Cost Optimization** - Spot instances for fault-tolerant batch workloads
4. **AZ Control** - Pin pools to specific availability zones or distribute across all

## Interface

Pools are defined using the `machine_pools` variable -- a list of pool objects. Each pool supports:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Pool name (must be unique) |
| `instance_type` | string | required | EC2 instance type |
| `replicas` | number | `2` | Fixed replica count (ignored if autoscaling enabled) |
| `autoscaling` | object | `null` | `{ enabled = bool, min = number, max = number }` |
| `spot` | object | `null` | `{ enabled = bool, max_price = string }` |
| `disk_size` | number | `300` | Root disk size in GB |
| `labels` | map(string) | `{}` | Node labels for workload targeting |
| `taints` | list(object) | `[]` | `[{ key, value, schedule_type }]` |
| `multi_az` | bool | `true` | Distribute across availability zones |
| `availability_zone` | string | `null` | Specific AZ (only if `multi_az = false`) |
| `subnet_id` | string | `null` | Override default subnet |

## Usage Examples

### Additional Worker Pool with Autoscaling

```hcl
machine_pools = [
  {
    name          = "batch-workers"
    instance_type = "m6i.2xlarge"
    autoscaling   = { enabled = true, min = 2, max = 10 }
    labels        = { "workload-type" = "batch", "team" = "data-engineering" }
    taints        = [{ key = "workload-type", value = "batch", schedule_type = "NoSchedule" }]
  }
]
```

### GPU Spot Pool for ML Training

```hcl
machine_pools = [
  {
    name          = "ml-training"
    instance_type = "p3.2xlarge"
    spot          = { enabled = true, max_price = "3.50" }
    autoscaling   = { enabled = true, min = 0, max = 5 }
    disk_size     = 500
    labels        = { "node-role.kubernetes.io/gpu" = "", "spot" = "true" }
    taints        = [
      { key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" },
      { key = "spot", value = "true", schedule_type = "PreferNoSchedule" }
    ]
  }
]
```

### Bare Metal for OpenShift Virtualization

```hcl
machine_pools = [
  {
    name          = "virt"
    instance_type = "m6i.metal"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/virtualization" = "" }
    taints        = [{ key = "virtualization", value = "true", schedule_type = "NoSchedule" }]
  }
]
```

### Multiple Pools

```hcl
machine_pools = [
  {
    name          = "compute"
    instance_type = "c5.2xlarge"
    autoscaling   = { enabled = true, min = 1, max = 20 }
  },
  {
    name          = "gpu-spot"
    instance_type = "g4dn.xlarge"
    spot          = { enabled = true, max_price = "" }
    autoscaling   = { enabled = true, min = 0, max = 3 }
    labels        = { "node-role.kubernetes.io/gpu" = "" }
    taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  }
]
```

## Understanding Taints and Tolerations

### What are Taints?

Taints are applied to nodes and repel pods that don't tolerate them. Think of taints as "keep out" signs on nodes.

### Taint Effects

| Effect | Behavior |
|--------|----------|
| `NoSchedule` | Pods without matching toleration will NOT be scheduled |
| `PreferNoSchedule` | Scheduler tries to avoid, but may still schedule if necessary |
| `NoExecute` | Existing pods without toleration are evicted |

### Scheduling Workloads on Tainted Nodes

To schedule a pod on a tainted node, add a matching toleration and node selector:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-job
spec:
  template:
    spec:
      tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "batch"
        effect: "NoSchedule"
      nodeSelector:
        workload-type: batch
      containers:
      - name: batch
        image: my-batch-image
```

## GPU Workloads

### Installing NVIDIA GPU Operator

For GPU workloads, install the NVIDIA GPU Operator:

```bash
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm repo update
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set operator.defaultRuntime=crio
```

### Scheduling GPU Workloads

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: ml-training
spec:
  template:
    spec:
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      - key: "spot"
        operator: "Equal"
        value: "true"
        effect: "PreferNoSchedule"
      nodeSelector:
        node-role.kubernetes.io/gpu: ""
      containers:
      - name: training
        image: my-ml-image
        resources:
          limits:
            nvidia.com/gpu: 1
```

## Spot Instance Considerations

### When to Use Spot Instances

**Good for:** ML model training, batch data processing, CI/CD build jobs, rendering, dev/test.

**Avoid for:** Stateful applications, long-running services, real-time applications, databases.

### Handling Spot Interruptions

AWS provides a 2-minute warning before spot termination. Use checkpointing, graceful shutdown handlers, and PodDisruptionBudgets:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ml-training-pdb
spec:
  minAvailable: 0
  selector:
    matchLabels:
      app: ml-training
```

## Outputs

| Name | Description |
|------|-------------|
| `machine_pools` | Map of created pools with ID, instance type, replicas, autoscaling, spot, labels |
| `pool_names` | List of created pool names |
| `pool_count` | Number of additional pools created |

## Administrator Notes

### Capacity Planning

- **Default Pool**: Leave room for system workloads (control plane, infra)
- **Additional Pools**: Size based on workload requirements
- **GPU Spot Pools**: Monitor spot availability in your region; set min=0 for scale-to-zero

### Cost Management

1. **Right-size instances** - Match instance type to workload needs
2. **Use autoscaling** - Scale down during low usage
3. **Scale to zero** - For sporadic workloads like ML training
4. **Monitor spot prices** - Set appropriate max price limits (empty string = on-demand cap)

### Monitoring

```bash
# Check machine pool status
oc get machinepool -A

# Check nodes in a specific pool
oc get nodes -l node.kubernetes.io/machinepool=batch-workers

# Check GPU nodes
oc get nodes -l node-role.kubernetes.io/gpu=
```

See [docs/MACHINE-POOLS.md](../../../docs/MACHINE-POOLS.md) for additional examples including ARM/Graviton, high-memory, and monitoring-dedicated pools.
