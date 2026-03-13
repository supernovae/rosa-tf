# AutoNode (Karpenter) on ROSA HCP

> **Technology Preview -- Not for Production Use**
>
> AutoNode (Karpenter) on ROSA HCP is a **Technology Preview** feature. Technology Preview features are not fully supported under Red Hat subscription service level agreements, may not be functionally complete, and are not intended for production use. Red Hat does not guarantee the stability of Technology Preview features or that a migration path will exist from Technology Preview to General Availability (GA). Clusters with AutoNode enabled should be treated as **disposable test environments**.
>
> Support cases for Technology Preview features are limited to Severity 3 and 4. There may not be any migration path from Technology Preview to GA -- a full reinstall of the GA version may be required and customer data may need to be migrated or may be lost.
>
> For full details see: https://access.redhat.com/support/offerings/techpreview

## Overview

AutoNode replaces traditional ROSA machine pool autoscaling with [Karpenter](https://karpenter.sh/), a Kubernetes-native node autoscaler. Karpenter watches for unschedulable pods, selects optimal instance types using bin-packing, and launches nodes directly via EC2 -- bypassing the machine pool abstraction entirely.

Key benefits over machine pool autoscaling:

- **Faster scaling** -- nodes launch in seconds, not minutes
- **Bin-packing** -- Karpenter picks the cheapest instance that fits pending pods
- **Multi-instance-type pools** -- a single NodePool can span many instance types
- **Spot with fallback** -- pair Spot and On-Demand pools with weights
- **Consolidation** -- automatically replaces underutilized nodes with smaller ones

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Terraform (this module)                                 │
│                                                          │
│  modules/cluster/autonode/        IAM role + policy,     │
│                                   subnet discovery tags  │
│                                                          │
│  modules/cluster/autonode-pool/   Karpenter NodePool     │
│                                   CRDs on the cluster    │
└──────────────┬───────────────────────────┬───────────────┘
               │                           │
               ▼                           ▼
       AWS IAM / EC2                 Kubernetes API
       (role, tags)               (NodePool resources)
               │                           │
               └───────────┬───────────────┘
                           ▼
                   Karpenter Controller
                   (managed by ROSA HCP)
                           │
                           ▼
                   EC2 Instances (nodes)
```

## Requirements

- ROSA HCP cluster on OpenShift 4.19+
- `us-east-1` region (private preview limitation)
- ROSA CLI (`rosa`) installed for the manual enablement step
- For private preview: cluster provisioned on the AutoNode shard via `cluster_properties`

## Deployment Workflow

AutoNode requires a **three-phase deployment** because Karpenter CRDs only exist on the cluster after the manual enablement step.

### Phase 1: Infrastructure + IAM

Create the cluster and AutoNode IAM resources:

```bash
cd environments/commercial-hcp   # or stage-hcp

terraform apply -var-file=cluster-dev.tfvars
```

This creates:
- VPC, ROSA HCP cluster, IAM roles
- Karpenter controller IAM role with OIDC trust
- Karpenter IAM policy (EC2, IAM, SSM, SQS, Pricing)
- `ec2:CreateTags` permission on the control-plane-operator role
- `karpenter.sh/discovery` tags on private subnets

### Phase 2: Enable AutoNode (manual)

Run the output command to enable AutoNode on the cluster:

```bash
terraform output -raw rosa_enable_autonode_command | bash
```

This executes:
```bash
rosa edit cluster -c <cluster_id> --autonode=enabled --autonode-iam-role-arn=<role_arn>
```

Wait ~5 minutes for Karpenter CRDs to appear:

```bash
oc get crd | grep karpenter
# Expected: ec2nodeclasses.karpenter.k8s.aws, nodeclaims.karpenter.sh, nodepools.karpenter.sh
```

### Phase 3: Deploy NodePools + GitOps Layers

Apply with GitOps and your pool definitions:

```bash
terraform apply \
  -var-file=cluster-dev.tfvars \
  -var-file=gitops-dev.tfvars \
  -var-file=openshiftai.tfvars   # optional, if using AI layers
```

Verify NodePools are ready:

```bash
oc get nodepools
oc get nodeclaims
```

## Pool Configuration Reference

Pools are defined in the `autonode_pools` variable. The format supports simple through complex configurations.

### Minimal Pool

Only `name` and `instance_type` are required. Everything else uses sensible defaults (Spot pricing, 30s consolidation delay, 30-day node expiry):

```hcl
autonode_pools = [
  { name = "general", instance_type = "m6a.2xlarge" }
]
```

### Multi-Instance-Type Pool

Karpenter picks the best-fit instance from the list based on pending pod requirements and current Spot pricing:

```hcl
autonode_pools = [{
  name           = "compute"
  instance_types = ["m6a.2xlarge", "m6a.4xlarge", "m7a.2xlarge", "m6i.2xlarge"]
  capacity_type  = "spot"
  limits         = { cpu = "64", memory = "256Gi" }
  expire_after   = "168h"
}]
```

### GPU Pool with Taints

Taints ensure only GPU-tolerant workloads are scheduled on expensive GPU nodes:

```hcl
autonode_pools = [{
  name          = "gpu-l40"
  instance_type = "g6e.2xlarge"
  capacity_type = "spot"
  labels = {
    "node-role.autonode/gpu" = ""
  }
  taints = [{
    key           = "nvidia.com/gpu"
    value         = "true"
    schedule_type = "NoSchedule"
  }]
  weight            = 10
  consolidate_after = "10m"
}]
```

### Spot + On-Demand Fallback

Use `weight` to prefer cheaper Spot nodes. When Spot capacity is unavailable, the On-Demand pool catches pending pods:

```hcl
autonode_pools = [
  {
    name           = "compute-spot"
    instance_types = ["m6a.2xlarge", "m6a.4xlarge"]
    capacity_type  = "spot"
    weight         = 100    # preferred
  },
  {
    name           = "compute-fallback"
    instance_types = ["m6a.2xlarge", "m6a.4xlarge"]
    capacity_type  = "on-demand"
    weight         = 1      # lower priority
    consolidation_policy = "WhenEmpty"
    consolidate_after    = "5m"
  }
]
```

### Field Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | *required* | NodePool name (must be unique) |
| `instance_type` | string | `""` | Single instance type (use this OR `instance_types`) |
| `instance_types` | list(string) | `[]` | Multiple types; Karpenter picks best fit |
| `capacity_type` | string | `"spot"` | `"spot"` or `"on-demand"` |
| `node_class` | string | `"default"` | EC2NodeClass name |
| `labels` | map(string) | `{}` | Pod template labels (`kubernetes.io` domain auto-filtered) |
| `taints` | list(object) | `[]` | `{key, value (optional), schedule_type}` |
| `limits` | map(string) | `{}` | Max resources the pool can provision (e.g. `{cpu = "100"}`) |
| `weight` | number | `0` | Priority between pools; higher = preferred |
| `expire_after` | string | `"720h"` | Node TTL before forced replacement (30 days) |
| `consolidation_policy` | string | `"WhenEmptyOrUnderutilized"` | `"WhenEmpty"` only removes nodes with zero non-daemonset pods |
| `consolidate_after` | string | `"30s"` | Delay before consolidation begins after conditions are met |

## Known Limitations

These limitations apply during the Technology Preview period:

1. **ARM/Graviton not available** -- the default `EC2NodeClass` only contains amd64 AMIs. ARM instance types (c7g, m7g, etc.) will fail to launch with "Instance launch failed" errors.

2. **Manual enablement step** -- `rosa edit cluster --autonode=enabled` must be run manually between Phase 1 and Phase 3. There is no Terraform resource for this today.

3. **`kubernetes.io` label restriction** -- Karpenter rejects `kubernetes.io` and `k8s.io` domain labels in `spec.template.metadata.labels`. The module automatically filters these out. Use custom domains instead (e.g. `node-role.autonode/gpu` instead of `node-role.kubernetes.io/gpu`).

4. **NodePool CRD references** -- During private preview, NodePools must reference `EC2NodeClass` (group: `karpenter.k8s.aws`), not `OpenshiftEC2NodeClass`. The module defaults handle this correctly.

5. **No migration path guaranteed** -- Red Hat does not guarantee a migration path from Technology Preview to GA. You may need to fully reinstall the cluster.

6. **Region restriction** -- Currently limited to `us-east-1`.

## Teardown

Before destroying a cluster with AutoNode enabled, delete all Karpenter resources first to avoid orphaned EC2 instances:

```bash
# Delete all NodePools (stops new node creation)
oc delete nodepool --all

# Delete all NodeClaims (terminates existing nodes)
oc delete nodeclaim --all

# Verify no Karpenter-managed nodes remain
oc get nodes -l karpenter.sh/nodepool

# Now safe to destroy
terraform destroy -var-file=cluster-dev.tfvars
```

Alternatively, set `skip_k8s_destroy = true` in your tfvars before `terraform destroy` to skip Kubernetes resource deletion (useful when the cluster API is already unreachable).

## Related Files

- `modules/cluster/autonode/` -- IAM role, policy, and subnet tagging
- `modules/cluster/autonode-pool/` -- Karpenter NodePool CRD management
- `examples/autonode.tfvars` -- Example pool configurations
- `environments/commercial-hcp/` -- Production environment (autonode wired in)
- `environments/stage-hcp/` -- Test environment (gitignored, for local experimentation)
