# AutoNode Pool Module

> **Technology Preview -- Not for Production Use**
>
> AutoNode (Karpenter) on ROSA HCP is a Technology Preview feature. Technology Preview features are not fully supported under Red Hat subscription service level agreements, may not be functionally complete, and are not intended for production use. Clusters with AutoNode enabled should be treated as disposable test environments.
>
> See: https://access.redhat.com/support/offerings/techpreview

Creates Karpenter `NodePool` custom resources on the cluster. Each pool maps to a single NodePool CR controlling instance type(s), capacity type, labels, taints, resource limits, and consolidation behavior.

## Prerequisites

- AutoNode must be enabled on the cluster (`rosa edit cluster --autonode=enabled`)
- Karpenter CRDs must be present (~5 minutes after enabling AutoNode)
- `kubectl` provider must be configured with cluster authentication

## Usage

```hcl
module "autonode_pools" {
  source = "../../modules/cluster/autonode-pool"
  count  = var.enable_autonode && var.install_gitops && !var.skip_k8s_destroy ? 1 : 0

  autonode_pools   = var.autonode_pools
  skip_k8s_destroy = var.skip_k8s_destroy
}
```

## Pool Definitions

Pools range from minimal to complex. Only `name` is truly required; `instance_type` or `instance_types` specifies what to launch.

**Simple:**
```hcl
autonode_pools = [
  { name = "general", instance_type = "m6a.2xlarge" }
]
```

**Multi-type with limits:**
```hcl
autonode_pools = [{
  name           = "compute"
  instance_types = ["m6a.2xlarge", "m6a.4xlarge", "m7a.2xlarge"]
  limits         = { cpu = "64", memory = "256Gi" }
}]
```

**GPU with taints:**
```hcl
autonode_pools = [{
  name          = "gpu-l40"
  instance_type = "g6e.2xlarge"
  labels        = { "node-role.autonode/gpu" = "" }
  taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  weight        = 10
  consolidate_after = "10m"
}]
```

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `autonode_pools` | list(object) | no | `[]` | Karpenter NodePool definitions (see field reference below) |
| `node_class_group` | string | no | `"karpenter.k8s.aws"` | API group for nodeClassRef |
| `node_class_kind` | string | no | `"EC2NodeClass"` | Kind for nodeClassRef |
| `skip_k8s_destroy` | bool | no | `false` | Skip K8s resource deletion on destroy |

### Pool Object Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | *required* | NodePool name |
| `instance_type` | string | `""` | Single instance type (use this OR `instance_types`) |
| `instance_types` | list(string) | `[]` | Multiple types; Karpenter picks best fit |
| `capacity_type` | string | `"spot"` | `"spot"` or `"on-demand"` |
| `node_class` | string | `"default"` | EC2NodeClass name |
| `labels` | map(string) | `{}` | Pod template labels |
| `taints` | list(object) | `[]` | `{key, value (optional), schedule_type}` |
| `limits` | map(string) | `{}` | Max resources (e.g. `{cpu = "100"}`) |
| `weight` | number | `0` | Pool priority; higher = preferred |
| `expire_after` | string | `"720h"` | Node TTL before replacement |
| `consolidation_policy` | string | `"WhenEmptyOrUnderutilized"` | When to consolidate |
| `consolidate_after` | string | `"30s"` | Delay before consolidation |

## Outputs

| Name | Description |
|------|-------------|
| `nodepool_names` | Names of the created Karpenter NodePool resources |

## Label Filtering

Karpenter rejects `kubernetes.io` and `k8s.io` domain labels in `spec.template.metadata.labels`. This module automatically filters them from the template labels. Use custom domains instead:

- `node-role.autonode/gpu` (not `node-role.kubernetes.io/gpu`)
- `workload.autonode/monitoring` (not `workload.kubernetes.io/monitoring`)

Labels on `metadata.labels` (the resource-level labels, not the pod template) are not filtered and retain `app.kubernetes.io/managed-by: terraform`.

## See Also

- [docs/AUTONODE.md](../../../docs/AUTONODE.md) -- full deployment guide and known limitations
- [modules/cluster/autonode/](../autonode/) -- companion module for IAM and subnet tagging
- [examples/autonode.tfvars](../../../examples/autonode.tfvars) -- example configurations
