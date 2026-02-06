# Machine Pools Module

This module creates optional additional machine pools for ROSA Classic clusters, enabling workload isolation, specialized compute (GPU), and cost optimization through spot instances.

## Overview

ROSA clusters are created with a default worker machine pool. This module allows you to create additional pools for:

1. **Workload Isolation** - Separate pools for different teams, environments, or workload types
2. **Specialized Compute** - GPU instances for ML/AI workloads
3. **Cost Optimization** - Spot instances for fault-tolerant batch workloads

## Machine Pool Types

### Additional Worker Pool

A general-purpose machine pool for workload isolation. Use cases:

- **Team Isolation**: Dedicate nodes to specific teams
- **Workload Separation**: Isolate batch jobs from interactive workloads
- **Resource Guarantees**: Ensure capacity for critical applications
- **Different Instance Types**: Use memory-optimized or compute-optimized instances

### GPU Spot Instance Pool

A cost-optimized pool for GPU workloads:

- **Up to 90% Cost Savings**: Spot instances are significantly cheaper
- **Scale from Zero**: Only pay when workloads are running
- **GPU Isolation**: Pre-configured taints prevent non-GPU workloads
- **Batch Processing**: Ideal for ML training, rendering, data processing

## Understanding Taints and Tolerations

### What are Taints?

Taints are applied to nodes and repel pods that don't tolerate them. Think of taints as "keep out" signs on nodes.

### Taint Effects

| Effect | Behavior |
|--------|----------|
| `NoSchedule` | Pods without matching toleration will NOT be scheduled |
| `PreferNoSchedule` | Scheduler tries to avoid, but may still schedule if necessary |
| `NoExecute` | Existing pods without toleration are evicted |

### Example: Batch Workload Isolation

**1. Configure the machine pool with a taint:**

```hcl
additional_pool_taints = [
  {
    key           = "workload-type"
    value         = "batch"
    schedule_type = "NoSchedule"
  }
]
```

**2. Add toleration to your batch workload:**

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
        node.kubernetes.io/machinepool: additional
      containers:
      - name: batch
        image: my-batch-image
```

## GPU Workload Configuration

### Default GPU Pool Taints

The GPU spot pool automatically applies these taints:

| Key | Value | Effect | Purpose |
|-----|-------|--------|---------|
| `nvidia.com/gpu` | `true` | `NoSchedule` | Only GPU-aware pods scheduled |
| `spot` | `true` | `PreferNoSchedule` | Warns pods about spot interruption |

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
      # Required: GPU taint
      - key: "nvidia.com/gpu"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      # Required: Spot instance taint
      - key: "spot"
        operator: "Equal"
        value: "true"
        effect: "PreferNoSchedule"
      nodeSelector:
        node-type: gpu
      containers:
      - name: training
        image: my-ml-image
        resources:
          limits:
            nvidia.com/gpu: 1
```

### Installing NVIDIA GPU Operator

For GPU workloads, you need the NVIDIA GPU Operator:

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm repo update

# Install GPU Operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set operator.defaultRuntime=crio
```

## Spot Instance Considerations

### When to Use Spot Instances

✅ **Good for:**
- ML model training (checkpointing supported)
- Batch data processing
- CI/CD build jobs
- Rendering workloads
- Development/testing

❌ **Avoid for:**
- Stateful applications
- Long-running services
- Real-time applications
- Databases

### Handling Spot Interruptions

1. **Use checkpointing** - Save state periodically
2. **Implement graceful shutdown** - Handle SIGTERM signals
3. **Use PodDisruptionBudgets** - Control disruption

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ml-training-pdb
spec:
  minAvailable: 0  # Allow all pods to be interrupted
  selector:
    matchLabels:
      app: ml-training
```

### Spot Instance Termination Notice

AWS provides a 2-minute warning before spot termination. The node receives a termination notice that can be detected:

```yaml
# Pod that monitors spot termination
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "save_checkpoint.sh"]
```

## Usage Examples

### Basic Additional Pool

```hcl
module "machine_pools" {
  source = "./modules/machine-pools"

  cluster_id = module.rosa_cluster.cluster_id

  # Enable additional worker pool
  create_additional_pool        = true
  additional_pool_name          = "batch-workers"
  additional_pool_instance_type = "m5.2xlarge"
  additional_pool_min_replicas  = 2
  additional_pool_max_replicas  = 10
  
  additional_pool_labels = {
    "workload-type" = "batch"
    "team"          = "data-engineering"
  }
  
  additional_pool_taints = [
    {
      key    = "workload-type"
      value  = "batch"
      effect = "NoSchedule"
    }
  ]
}
```

### GPU Spot Pool for ML Training

```hcl
module "machine_pools" {
  source = "./modules/machine-pools"

  cluster_id = module.rosa_cluster.cluster_id

  # Enable GPU spot pool
  create_gpu_spot_pool          = true
  gpu_spot_pool_name            = "ml-training"
  gpu_spot_pool_instance_type   = "p3.2xlarge"  # 1x V100 GPU
  gpu_spot_pool_min_replicas    = 0             # Scale to zero
  gpu_spot_pool_max_replicas    = 5
  gpu_spot_pool_disk_size       = 500           # For model storage
  
  gpu_spot_pool_labels = {
    "ml-framework" = "pytorch"
  }
}
```

### Both Pools

```hcl
module "machine_pools" {
  source = "./modules/machine-pools"

  cluster_id = module.rosa_cluster.cluster_id

  # Additional worker pool
  create_additional_pool        = true
  additional_pool_name          = "compute"
  additional_pool_instance_type = "c5.2xlarge"
  additional_pool_min_replicas  = 1
  additional_pool_max_replicas  = 20
  
  # GPU spot pool
  create_gpu_spot_pool          = true
  gpu_spot_pool_instance_type   = "g4dn.xlarge"
  gpu_spot_pool_max_replicas    = 3
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_id` | ID of the ROSA cluster | `string` | n/a | yes |
| `create_additional_pool` | Create additional worker pool | `bool` | `false` | no |
| `additional_pool_name` | Name of additional pool | `string` | `"additional"` | no |
| `additional_pool_instance_type` | Instance type | `string` | `"m5.xlarge"` | no |
| `additional_pool_min_replicas` | Min replicas (autoscaling) | `number` | `1` | no |
| `additional_pool_max_replicas` | Max replicas (autoscaling) | `number` | `5` | no |
| `additional_pool_labels` | Node labels | `map(string)` | `{}` | no |
| `additional_pool_taints` | Node taints | `list(object)` | `[]` | no |
| `create_gpu_spot_pool` | Create GPU spot pool | `bool` | `false` | no |
| `gpu_spot_pool_instance_type` | GPU instance type | `string` | `"g4dn.xlarge"` | no |
| `gpu_spot_pool_min_replicas` | Min replicas (0 = scale to zero) | `number` | `0` | no |
| `gpu_spot_pool_max_replicas` | Max replicas | `number` | `3` | no |
| `gpu_spot_max_price` | Max spot price (empty = on-demand) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| `additional_pool_id` | ID of additional machine pool |
| `gpu_spot_pool_id` | ID of GPU spot machine pool |
| `workload_scheduling_info` | YAML examples for scheduling |

## Administrator Notes

### Capacity Planning

- **Default Pool**: Leave room for system workloads
- **Additional Pool**: Size based on workload requirements
- **GPU Spot Pool**: Monitor spot availability in your region

### Cost Management

1. **Right-size instances** - Match instance type to workload needs
2. **Use autoscaling** - Scale down during low usage
3. **Scale to zero** - For sporadic workloads like ML training
4. **Monitor spot prices** - Set appropriate max price limits

### Security Considerations

- Machine pools inherit cluster security settings
- Taints provide workload isolation, not security boundaries
- Consider network policies for additional isolation
- GPU workloads may require additional security review

### Monitoring

Monitor machine pool health:

```bash
# Check machine pool status
oc get machinepool -A

# Check nodes in pool
oc get nodes -l node.kubernetes.io/machinepool=additional

# Check GPU nodes
oc get nodes -l node-type=gpu
```
