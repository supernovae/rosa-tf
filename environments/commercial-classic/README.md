# ROSA Classic Commercial Environment

This environment deploys ROSA Classic clusters in AWS Commercial regions.

## Quick Start

```bash
# Set your OCM token (from https://console.redhat.com/openshift/token)
export TF_VAR_ocm_token="your-offline-token"

# Initialize
terraform init

# Development cluster (single-AZ, public)
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

# Production cluster (multi-AZ, private)
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

## Environment Configurations

| File | Topology | Access | FIPS | KMS Mode | Use Case |
|------|----------|--------|------|----------|----------|
| `dev.tfvars` | Single-AZ | Public | Off | `provider_managed` | Development |
| `prod.tfvars` | Multi-AZ | Private | Off* | `create` | Production |

*Enable FIPS in prod.tfvars for regulated workloads (FedRAMP, HIPAA, PCI).

## KMS Encryption Modes

Three modes for encryption key management:

| Mode | Description | Cost Impact |
|------|-------------|-------------|
| `provider_managed` | AWS managed `aws/ebs` key (DEFAULT) | No extra cost |
| `create` | Terraform creates customer-managed key | ~$1/month per key |
| `existing` | Use your own KMS key ARN | Varies |

Two separate KMS modes for blast radius containment:
- `cluster_kms_mode` - For ROSA workers and etcd
- `infra_kms_mode` - For jump host, CloudWatch, S3, VPN

```hcl
# dev.tfvars - Default, uses AWS managed keys
cluster_kms_mode = "provider_managed"
infra_kms_mode   = "provider_managed"

# prod.tfvars - Customer-managed keys
cluster_kms_mode = "create"
infra_kms_mode   = "create"
etcd_encryption  = true  # Optional extra layer

# Bring your own keys
cluster_kms_mode    = "existing"
cluster_kms_key_arn = "arn:aws:kms:region:account:key/cluster-key-id"
infra_kms_mode      = "existing"
infra_kms_key_arn   = "arn:aws:kms:region:account:key/infra-key-id"
```

**Note:** ROSA Classic already encrypts EBS at rest. The `etcd_encryption` option adds an additional encryption layer for etcd data when using custom KMS.

## Key Differences from GovCloud

| Feature | Commercial | GovCloud |
|---------|------------|----------|
| Public Clusters | ✅ Supported | ❌ Private only |
| Private Clusters | ✅ Supported | ✅ Required |
| FIPS Mode | Optional | Required |
| KMS Encryption | Optional | Recommended |
| Console URL | console.redhat.com | console.openshiftusgov.com |

| API URL | api.openshift.com | api.openshiftusgov.com |

> **Note**: Private clusters use AWS PrivateLink for Red Hat SRE access. Public clusters allow SRE access via the public API endpoint.

## Cluster Access Patterns

### Public Cluster (dev default)

Direct internet access to API and console:

```bash
# After cluster creation, get credentials
terraform output -raw cluster_console_url
terraform output -raw cluster_admin_password

# Login via oc CLI
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)
```

### Private Cluster (prod default)

Requires jump host or VPN:

```bash
# Via jump host (SSM)
aws ssm start-session --target $(terraform output -raw jumphost_instance_id)
# Then oc login from within the jump host

# Or via SSM port forwarding
terraform output -raw ssm_port_forward_command
# Run the command, then login via forwarded port
```

## Cost Estimate (Default Configuration)

ROSA Classic runs all nodes (control plane, infra, workers) in your AWS account.

| Component | Dev (7 nodes) | Prod (9 nodes) |
|-----------|---------------|----------------|
| EC2 Instances (all 7/9 nodes) | ~$1,050/mo | ~$1,350/mo |
| OpenShift Fee (workers only) | ~$250/mo (2) | ~$375/mo (3) |
| NAT Gateway | ~$32/mo | ~$96/mo |
| **Total Estimate** | **~$1,330/mo** | **~$1,820/mo** |

*EC2: m5.xlarge ~$140/mo, r5.xlarge ~$182/mo. OpenShift fee ~$0.171/hr per 4 vCPUs (workers only, not CP/infra).*

**Cost Savings Options:**
- **EC2 Reserved Instances**: Save up to 40-60% on EC2 costs with 1 or 3-year commitments
- **OpenShift 1-Year Commit**: Discounted hourly rate with annual commitment via AWS Marketplace
- **Red Hat Private Offer**: Contact your Red Hat seller for custom pricing up to 3 years

## Customization

### Enable FIPS for Regulated Workloads

```hcl
# In prod.tfvars or custom tfvars
fips = true
```

**Note:** FIPS cannot be changed after cluster creation.

### Use Transit Gateway Instead of NAT

```hcl
egress_type        = "tgw"
transit_gateway_id = "tgw-0123456789abcdef0"
```

### Add GPU Spot Instances

See [docs/MACHINE-POOLS.md](../../docs/MACHINE-POOLS.md) for comprehensive examples.

```hcl
machine_pools = [
  {
    name          = "gpu-spot"
    instance_type = "g4dn.xlarge"  # T4 GPU
    spot          = { enabled = true }
    autoscaling   = { enabled = true, min = 0, max = 5 }
    multi_az      = false
    labels        = { "node-role.kubernetes.io/gpu" = "", "spot" = "true" }
    taints        = [
      { key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" },
      { key = "spot", value = "true", schedule_type = "PreferNoSchedule" }
    ]
  }
]
```

### Enable GitOps

```hcl
install_gitops        = true
enable_layer_terminal = true
```

### Cluster Autoscaler

ROSA Classic supports cluster-wide autoscaling. Enable the cluster autoscaler to automatically adjust cluster size based on workload demands.

```hcl
# Enable cluster autoscaler
cluster_autoscaler_enabled = true

# Set maximum total nodes (control plane + infra + workers)
autoscaler_max_nodes_total = 50

# Scale-down settings
autoscaler_scale_down_enabled              = true
autoscaler_scale_down_utilization_threshold = "0.5"  # Scale down if < 50% utilized
autoscaler_scale_down_delay_after_add      = "10m"   # Wait 10 min after scale up
autoscaler_scale_down_unneeded_time        = "10m"   # Node must be idle 10 min
```

**How It Works:**

| Component | Purpose |
|-----------|---------|
| **Cluster Autoscaler** | Controls cluster-wide scaling behavior (thresholds, timing, limits) |
| **Machine Pool Autoscaling** | Controls individual pool scaling (min/max replicas per pool) |

Both must be enabled for full autoscaling:
1. Enable `cluster_autoscaler_enabled = true` (cluster-wide settings)
2. Add machine pools with `autoscaling = { enabled = true, min = X, max = Y }`

**Example: Production with Autoscaling**

```hcl
# Enable autoscaling
cluster_autoscaler_enabled = true
autoscaler_max_nodes_total = 100

# Add autoscaling machine pool
machine_pools = [
  {
    name          = "workers"
    instance_type = "m5.xlarge"
    autoscaling   = { enabled = true, min = 3, max = 20 }
  }
]
```

## State Management

Each cluster needs its own state file:

```bash
# Dev cluster
terraform init -backend-config="key=rosa/commercial/dev/terraform.tfstate"
terraform apply -var-file=dev.tfvars

# Prod cluster
terraform init -backend-config="key=rosa/commercial/prod/terraform.tfstate"
terraform apply -var-file=prod.tfvars
```

## Destroying Clusters

```bash
terraform destroy -var-file=dev.tfvars
# or
terraform destroy -var-file=prod.tfvars
```

**Note:** Cluster destruction takes 15-30 minutes.
