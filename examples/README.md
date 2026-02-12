# Example tfvars Files

Complete, standalone example configurations showing specific use cases. These mirror the structure of `dev.tfvars` with targeted configurations for each scenario.

**Usage:** Copy to your environment folder, customize `cluster_name`/`aws_region`, and apply.

## Available Examples

### `zeroegress.tfvars`

Zero-egress (air-gapped) cluster with no internet access. HCP only.

**Key configuration:**
```hcl
zero_egress     = true   # Enables air-gapped mode (auto-sets egress_type="none")
private_cluster = true   # Required for zero egress
create_ecr      = true   # ECR for operator mirroring
create_client_vpn = true # Required for cluster access
ssm_enabled     = true   # Node debugging via SSM
install_gitops  = false  # Disabled until operators mirrored
```

**After deployment:**
1. Connect via VPN
2. Apply IDMS: `oc apply -f outputs/idms-config.yaml`
3. Mirror operators to ECR: `oc adm catalog mirror ...`
4. Enable GitOps (optional)

### `observability.tfvars`

Dedicated monitoring nodes on Graviton (ARM) for cost-efficient observability (Prometheus + Loki).
Uses `c7g.4xlarge` instances (~30% cheaper than equivalent x86) with `PreferNoSchedule` taints.

**Key configuration:**
```hcl
# Dedicated Graviton monitoring pool with PreferNoSchedule taint
machine_pools = [
  {
    name          = "monitoring"
    instance_type = "c7g.4xlarge"  # Graviton3 ARM - best price-performance
    replicas      = 4
    labels        = { "node-role.kubernetes.io/monitoring" = "" }
    taints        = [{ key = "workload", value = "monitoring", schedule_type = "PreferNoSchedule" }]
  }
]

# LokiStack uses these to land on dedicated nodes
monitoring_node_selector = { "node-role.kubernetes.io/monitoring" = "" }
monitoring_tolerations   = [{ key = "workload", value = "monitoring", effect = "PreferNoSchedule", operator = "Equal" }]
```

### `ocpvirtualization.tfvars`

Bare metal nodes for OpenShift Virtualization (KubeVirt).

**Key configuration:**
```hcl
# Bare metal machine pool with taints
machine_pools = [
  {
    name          = "virt"
    instance_type = "m5.metal"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/virtualization" = "" }
    taints        = [{ key = "virtualization", value = "true", schedule_type = "NoSchedule" }]
  }
]

# HyperConverged CR uses these to land on bare metal nodes
virt_node_selector = { "node-role.kubernetes.io/virtualization" = "" }
virt_tolerations   = [{ key = "virtualization", value = "true", effect = "NoSchedule", operator = "Equal" }]
```

### `byovpc.tfvars`

Deploy a second ROSA HCP cluster into an existing VPC (BYO-VPC). Uses non-overlapping CIDRs to avoid conflicts with the first cluster.

**Key configuration:**
```hcl
# Point to an existing VPC and its subnets
existing_vpc_id             = "vpc-0123456789abcdef0"
existing_private_subnet_ids = ["subnet-...", "subnet-...", "subnet-..."]

# Non-overlapping CIDRs (first cluster uses 10.128.0.0/14 + 172.30.0.0/16)
pod_cidr     = "10.132.0.0/14"
service_cidr = "172.31.0.0/16"
```

**Topology inference:** 1 private subnet = single-AZ, 3 = multi-AZ (auto-detected).

See `docs/BYO-VPC.md` for CIDR planning, anti-pattern warnings, and multi-cluster guidance.

## Usage

### Step 1: Copy to your environment

```bash
# For zero egress (HCP only)
cp examples/zeroegress.tfvars environments/commercial-hcp/my-cluster.tfvars

# For observability
cp examples/observability.tfvars environments/commercial-hcp/my-cluster.tfvars

# For virtualization
cp examples/ocpvirtualization.tfvars environments/commercial-hcp/my-cluster.tfvars

# For BYO-VPC (second cluster in existing VPC)
cp examples/byovpc.tfvars environments/commercial-hcp/my-cluster-2.tfvars
```

### Step 2: Customize required values

Edit the copied file and change:
- `cluster_name` - Your unique cluster name
- `aws_region` - Your target region
- `openshift_version` - Your desired OCP version

### Step 3: Deploy

```bash
cd environments/commercial-hcp
terraform init
terraform apply -var-file="my-cluster.tfvars"
```

## How This Works

The examples use the **standard `machine_pools` variable** - the same one used in `dev.tfvars`. This keeps things simple:

1. **Machine pools** are defined in tfvars with labels and taints
2. **Node selector** tells the operator where to schedule pods
3. **Tolerations** allow pods to run on tainted nodes

No special modules or complex logic - just standard Kubernetes scheduling concepts.

## Combining Features

To have both monitoring AND virtualization on dedicated nodes:

```hcl
machine_pools = [
  {
    name          = "monitoring"
    instance_type = "m5.4xlarge"
    replicas      = 3
    labels        = { "node-role.kubernetes.io/monitoring" = "" }
    taints        = [{ key = "workload", value = "monitoring", schedule_type = "NoSchedule" }]
  },
  {
    name          = "virt"
    instance_type = "m5.metal"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/virtualization" = "" }
    taints        = [{ key = "virtualization", value = "true", schedule_type = "NoSchedule" }]
  }
]

enable_layer_monitoring     = true
enable_layer_virtualization = true

# Monitoring placement
monitoring_node_selector = { "node-role.kubernetes.io/monitoring" = "" }
monitoring_tolerations   = [{ key = "workload", value = "monitoring", effect = "NoSchedule", operator = "Equal" }]

# Virtualization placement
virt_node_selector = { "node-role.kubernetes.io/virtualization" = "" }
virt_tolerations   = [{ key = "virtualization", value = "true", effect = "NoSchedule", operator = "Equal" }]
```

## GovCloud Adjustments

For GovCloud environments, also set:

```hcl
aws_region       = "us-gov-west-1"
private_cluster  = true
cluster_kms_mode = "create"
infra_kms_mode   = "create"
create_client_vpn = true
```

## Cost Estimates

| Configuration | Instance Types | Monthly Cost (approx) |
|--------------|----------------|----------------------|
| Base cluster (3 workers) | 3x m5.xlarge | ~$500 |
| Zero egress (no NAT) | 3x m5.xlarge | ~$400 (no NAT costs) |
| + Monitoring pool | 3x m5.4xlarge | +$1,500 |
| + Virtualization pool | 2x m5.metal | +$6,700 |
| + VPN (Client VPN) | per connection | ~$75 + $0.10/hr |

## Zero Egress Notes

Zero egress clusters require additional setup after deployment:

1. **IDMS Application** - Apply the generated ImageDigestMirrorSet
2. **Operator Mirroring** - Mirror required operators to your ECR
3. **GitOps** - Can be enabled after operators are mirrored

See `examples/zeroegress.tfvars` for detailed next-steps instructions.
