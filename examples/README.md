# Example tfvars Files

Scenario configurations and overlays for the environment roots. Use Terraform pinned in `.terraform-version` and the committed provider lockfiles; see [provider upgrade notes](../docs/PROVIDER-UPGRADE.md).

| Files | Kind | Target |
| --- | --- | --- |
| zeroegress, observability, ocpvirtualization, certmanager, byovpc | Complete cluster scenarios | commercial-hcp |
| byovpc-classic-prod | Complete cluster scenario | commercial-classic |
| openshiftai, netappstorage, gitops-workloads | GitOps overlays; require a cluster tfvars base | All four cluster roots, subject to platform prerequisites |
| autonode | Compute overlay; requires a cluster tfvars base | commercial-hcp |
| cluster-only | Phase 1 safety overlay, passed last | All four cluster roots |

File names above have the `.tfvars` extension. Replace example names, domains, IDs and CIDRs before use. Do not commit credentials or customized private tfvars.

## Available Examples

### NetApp container and VM storage

[netappstorage.tfvars](netappstorage.tfvars) is a platform overlay for all four roots,
with certified Trident, separate filesystem/SVM credentials, trusted-CA requirements,
manual operator approval and explicit node preparation. It requires real endpoint,
CA and separately delivered Secret values before use. See
[NetApp storage guidance](../docs/NETAPP-STORAGE.md) and the
[PVC, VM and snapshot examples](netapp/README.md). Existing systems need the migration
checklist before adopting the new retained storage classes.

### Secure workload GitOps

[gitops-workloads.tfvars](gitops-workloads.tfvars) is an explicit workload overlay:
one repository, one delegated namespace, group-based access and manual sync with
pruning off. Copy [the harmless Kustomize example](gitops-workload/kustomization.yaml)
into your approved workload repository, then adjust the URL/path/groups. Do not
point the Application at Terraform-owned platform layers. See the
[GitOps deployment and migration guide](../docs/GITOPS.md) before applying.

### `zeroegress.tfvars`

Zero-egress (air-gapped) cluster with no internet access. HCP only.

**Key configuration:**
```hcl
zero_egress     = true   # Enables air-gapped mode (auto-sets egress_type="none")
private_cluster = true   # Required for zero egress
create_ecr      = true   # ECR for operator mirroring
create_client_vpn = true # Required for cluster access
install_gitops  = false  # Disabled until operators mirrored
```

**After deployment:**
1. Connect via VPN
2. Apply IDMS: `oc apply -f outputs/idms-config.yaml`
3. Mirror operators to ECR: `oc adm catalog mirror ...`
4. Enable GitOps (optional)

### `observability.tfvars`

Dedicated monitoring nodes on Graviton (ARM) for cost-efficient observability (Prometheus + Loki).
Uses memory-balanced `m7g.4xlarge` instances with soft `PreferNoSchedule` taints.
Verify ROSA regional support, image architectures and AZ capacity first. The
selector places Loki and user metrics on ARM; Vector remains on all workers.
Create the cluster/pools with `install_gitops=false` before the layer phase.
See [operations, dashboards and cost math](../docs/OBSERVABILITY.md) and
[optional AWS recovery](../docs/OBSERVABILITY-AWS-RECOVERY.md).

**Key configuration:**
```hcl
# Dedicated Graviton monitoring pool with PreferNoSchedule taint
machine_pools = [
  {
    name          = "monitoring"
    instance_type = "m7g.4xlarge"  # Benchmark against equal-memory x86 in your region
    replicas      = 3
    labels        = { "node-role.kubernetes.io/monitoring" = "" }
    taints        = [{ key = "workload", value = "monitoring", schedule_type = "PreferNoSchedule" }]
  }
]

# Loki and user Prometheus/Thanos Ruler/Alertmanager placement
monitoring_node_selector = { "node-role.kubernetes.io/monitoring" = "", "kubernetes.io/arch" = "arm64" }
monitoring_tolerations   = [{ key = "workload", value = "monitoring", effect = "PreferNoSchedule", operator = "Equal" }]
```

### Application observability examples

`observability/application.yaml` supplies a Service, ServiceMonitor and health
rule for an existing instrumented application. Adapt namespace, selectors and
ports, then verify a fresh scrape and log query. The optional
`observability/alertmanagerconfig.yaml` routes namespace alerts to a webhook
whose URL is supplied through an approved Secret; it does not ship credentials.
Test both firing and resolved notifications before calling the stack operational.

### `ocpvirtualization.tfvars`

Bare metal nodes for OpenShift Virtualization (KubeVirt).

**Key configuration:**
```hcl
# Bare metal machine pool with taints
machine_pools = [
  {
    name          = "virt"
    instance_type = "m6i.metal"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/virtualization" = "" }
    taints        = [{ key = "virtualization", value = "true", schedule_type = "NoSchedule" }]
  }
]

# HyperConverged CR uses these to land on bare metal nodes
virt_node_selector = { "node-role.kubernetes.io/virtualization" = "" }
virt_tolerations   = [{ key = "virtualization", value = "true", effect = "NoSchedule", operator = "Equal" }]
```

### `certmanager.tfvars`

Automated TLS certificate management with Let's Encrypt DNS01 challenge via Route53.

**Key configuration:**
```hcl
# Enable cert-manager layer
enable_layer_certmanager       = true
certmanager_create_hosted_zone = false
certmanager_hosted_zone_id     = "Z0123456789ABCDEF"
certmanager_hosted_zone_domain = "example.com"
certmanager_use_staging_issuer = true
certmanager_acme_email         = "platform-team@example.com"

# Pre-create wildcard certificate
certmanager_certificate_domains = [
  {
    name        = "apps-wildcard"
    namespace   = "openshift-ingress"
    secret_name = "custom-apps-default-cert"
    domains     = ["*.apps.example.com"]
  }
]
```

**After deployment:**
1. If zone was created, delegate DNS from registrar to AWS nameservers (shown in output)
2. ClusterIssuer `letsencrypt-production` is ready
3. Use explicit Certificate resources and the custom IngressController wildcard Secret. The community Routes integration is opt-in; see the [cert-manager guide](../modules/gitops-layers/certmanager/README.md).

**Note:** This public ACME example requires outbound HTTPS. cert-manager itself can use internal issuers in restricted networks; that requires a different issuer configuration.

### `autonode.tfvars`

> AutoNode (Red Hat build of Karpenter) is GA and fully supported on ROSA HCP. Requires OpenShift 4.19+ and ROSA CLI >= 1.2.61.

AutoNode (Karpenter) node autoscaling on ROSA HCP. Replaces traditional machine pool autoscaling with Karpenter's bin-packing scheduler. See [docs/AUTONODE.md](../docs/AUTONODE.md) for the full guide.

**Key configuration:**
```hcl
enable_autonode = true

# Simple pool (only name + instance_type required):
autonode_pools = [
  { name = "general", instance_type = "m6a.2xlarge" }
]

# Multi-type Spot with resource limits:
autonode_pools = [{
  name           = "compute-spot"
  instance_types = ["m6a.2xlarge", "m6a.4xlarge", "m7a.2xlarge"]
  capacity_type  = "spot"
  limits         = { cpu = "64", memory = "256Gi" }
}]

# GPU with taints and delayed consolidation:
autonode_pools = [{
  name              = "gpu-l40"
  instance_type     = "g6e.2xlarge"
  taints            = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  consolidate_after = "10m"
}]
```

**After deployment:**
1. Wait ~5 min for Karpenter CRDs: `oc get crd | grep karpenter`
2. Re-apply with `install_gitops = true` to deploy NodePools

AutoNode is enabled automatically via Terraform -- no manual CLI step required.

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

### `byovpc-classic-prod.tfvars`

Deploy a second ROSA Classic cluster into an existing VPC for production (multi-AZ, `us-east-1`).

**Key configuration:**
```hcl
# Point to an existing VPC and its subnets
existing_vpc_id             = "vpc-CHANGEME"
existing_private_subnet_ids = ["subnet-...", "subnet-...", "subnet-..."]

# Non-overlapping CIDRs
pod_cidr     = "10.132.0.0/14"
service_cidr = "172.31.0.0/16"

# Production settings
private_cluster = true
worker_node_count = 3
etcd_encryption   = true
```

See `docs/BYO-VPC.md` for workspace requirements and destroy order.

## Usage

Maintainers can check tracked tfvars syntax and input names with `uv run scripts/check-examples.py`. This does not replace a reviewed plan against the intended account and region.

### Step 1: Copy to your environment

```bash
# For zero egress (HCP only)
cp examples/zeroegress.tfvars environments/commercial-hcp/my-cluster.tfvars

# For observability
cp examples/observability.tfvars environments/commercial-hcp/my-cluster.tfvars

# For virtualization
cp examples/ocpvirtualization.tfvars environments/commercial-hcp/my-cluster.tfvars

# For cert-manager
cp examples/certmanager.tfvars environments/commercial-hcp/my-cluster.tfvars

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
terraform init -lockfile=readonly

# Phase 1: provision infrastructure without contacting the new cluster API.
terraform plan -var-file="my-cluster.tfvars" -var-file="../../examples/cluster-only.tfvars"
terraform apply -var-file="my-cluster.tfvars" -var-file="../../examples/cluster-only.tfvars"

# Establish VPN/private API connectivity before Phase 2.
# For examples already enabling GitOps, omit the safety overlay:
terraform plan -var-file="my-cluster.tfvars"
terraform apply -var-file="my-cluster.tfvars"
```

For examples that leave GitOps disabled (zero-egress and Classic BYO-VPC), complete their prerequisites and add a matching environment GitOps overlay in Phase 2. Zero-egress also requires mirrored operators.

Feature-only overlays are not standalone. For example, after provisioning the cluster and GPU pool as described in `openshiftai.tfvars`:

```bash
terraform plan -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars -var-file=../../examples/openshiftai.tfvars
terraform apply -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars -var-file=../../examples/openshiftai.tfvars
```

Later `-var-file` arguments replace earlier values; lists and maps are **not merged**. Combine machine pools in a single list. Keep the same base files and workspace on subsequent runs. Plans and state may contain secrets; protect saved artifacts.

HCP examples keep `cluster_autoscaler_enabled = false`: RHCS 1.7.7 does not support HCP cluster-wide tuning. Use individual machine-pool autoscaling (`autoscaling_enabled`, `min_replicas`, `max_replicas`; omit `replicas`) or supported AutoNode configurations.

## How This Works

The examples use the **standard `machine_pools` variable** - the same one used in `cluster-dev.tfvars`. This keeps things simple:

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
    instance_type = "m6i.4xlarge"
    replicas      = 3
    labels        = { "node-role.kubernetes.io/monitoring" = "" }
    taints        = [{ key = "workload", value = "monitoring", schedule_type = "NoSchedule" }]
  },
  {
    name          = "virt"
    instance_type = "m6i.metal"
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

For GovCloud HCP, start from `environments/govcloud-hcp/cluster-dev.tfvars` or
`cluster-prod.tfvars`: both default to zero-egress with a private management
path. Complete [mirroring and private connectivity](../docs/ZERO-EGRESS.md)
before adding feature overlays. Classic does not use this HCP zero-egress flag.

Start from the matching GovCloud environment sample; changing only the region is insufficient. Verify service, instance-type, operator and OpenShift-version availability in that partition. In particular, do not assume the commercial AutoNode overlay is supported there. Typical additional settings include:

```hcl
aws_region       = "us-gov-west-1"
private_cluster  = true
cluster_kms_mode = "create"
infra_kms_mode   = "create"
create_client_vpn = true
```

## Cost Planning

Obtain current estimates for your region with the [AWS Pricing Calculator](https://calculator.aws/). Include ROSA fees, worker and bare-metal instances, storage, NAT/endpoints, data transfer, VPN, backups and optional managed services. These samples are topology demonstrations, not price quotes or sizing guarantees.

## Zero Egress Notes

Zero egress clusters require additional setup after deployment:

1. **IDMS Application** - Apply the generated ImageDigestMirrorSet
2. **Operator Mirroring** - Mirror required operators to your ECR
3. **GitOps** - Can be enabled after operators are mirrored

See `examples/zeroegress.tfvars` for detailed next-steps instructions.
