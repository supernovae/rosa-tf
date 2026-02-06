# ROSA Classic GovCloud Environment

This environment deploys ROSA Classic clusters in AWS GovCloud with FedRAMP compliance.

## Quick Start

```bash
# Set your OCM token
export TF_VAR_ocm_token="your-token-from-console.openshiftusgov.com"

# Initialize
terraform init

# Deploy dev cluster (single-AZ, cost optimized)
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

# Deploy prod cluster (multi-AZ, HA)
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

## Environment Files

| File | Topology | Workers | NAT Gateways | Use Case |
|------|----------|---------|--------------|----------|
| `dev.tfvars` | Single-AZ | 2 | 1 | Development, testing |
| `prod.tfvars` | Multi-AZ | 3+ | 3 | Production |

## Creating Your Own Environment

Copy an existing tfvars and customize:

```bash
cp dev.tfvars staging.tfvars
# Edit staging.tfvars with your settings
terraform apply -var-file=staging.tfvars
```

## State Management

Each cluster should have its own state file. Options:

### Option 1: Separate State per Cluster (Recommended)

```bash
# Dev cluster state
terraform init -backend-config="key=rosa/dev/terraform.tfstate"
terraform apply -var-file=dev.tfvars

# Prod cluster state (different terminal/directory)
terraform init -backend-config="key=rosa/prod/terraform.tfstate"
terraform apply -var-file=prod.tfvars
```

### Option 2: Terraform Workspaces

```bash
terraform workspace new dev
terraform apply -var-file=dev.tfvars

terraform workspace new prod
terraform apply -var-file=prod.tfvars
```

## Security Posture

Both dev and prod maintain identical security:

| Feature | Dev | Prod |
|---------|-----|------|
| FIPS Mode | ✅ | ✅ |
| Private Cluster | ✅ | ✅ |
| STS Mode | ✅ | ✅ |
| KMS Encryption | ✅ | ✅ |
| etcd Encryption | ✅ | ✅ |

> **Note**: GovCloud clusters are always private and use AWS PrivateLink for Red Hat SRE access.

## KMS Encryption (Mandatory)

GovCloud requires customer-managed KMS keys for FedRAMP compliance (SC-12/SC-13).

| Mode | Description | Use Case |
|------|-------------|----------|
| `create` (DEFAULT) | Terraform creates customer-managed key | Most deployments |
| `existing` | Use your own KMS key ARN | Centralized key management |

**Note:** `provider_managed` is NOT available in GovCloud - FedRAMP requires customer control over cryptographic keys.

Two separate KMS modes for blast radius containment:
- `cluster_kms_mode` - For ROSA workers and etcd
- `infra_kms_mode` - For jump host, CloudWatch, S3, VPN

```hcl
# Default - Terraform manages the keys
cluster_kms_mode = "create"
infra_kms_mode   = "create"

# Bring your own keys
cluster_kms_mode    = "existing"
cluster_kms_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/cluster-key..."
infra_kms_mode      = "existing"
infra_kms_key_arn   = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/infra-key..."
```

The only differences are availability and cost:

| Aspect | Dev | Prod |
|--------|-----|------|
| Availability Zones | 1 | 3 |
| NAT Gateways | 1 | 3 |
| Worker Nodes | 2+ | 3+ |
| VPC Flow Logs | Optional | Enabled |
| Survives AZ Failure | ❌ | ✅ |

## Cost Estimate (Default Configuration)

ROSA Classic runs all nodes (control plane, infra, workers) in your AWS account.

| Component | Dev (7 nodes) | Prod (9 nodes) |
|-----------|---------------|----------------|
| EC2 Instances (all 7/9 nodes) | ~$1,200/mo | ~$1,550/mo |
| OpenShift Fee (workers only) | ~$250/mo (2) | ~$375/mo (3) |
| NAT Gateway | ~$36/mo | ~$108/mo |
| **Total Estimate** | **~$1,490/mo** | **~$2,030/mo** |

*GovCloud EC2 ~10-15% higher. OpenShift fee ~$0.171/hr per 4 vCPUs (workers only, not CP/infra).*

**Cost Savings Options:**
- **EC2 Reserved Instances**: Save up to 40-60% on EC2 costs with 1 or 3-year commitments
- **OpenShift 1-Year Commit**: Discounted hourly rate with annual commitment via AWS Marketplace
- **Red Hat Private Offer**: Contact your Red Hat seller for custom pricing up to 3 years

## Customizing Variables

Override any variable in your tfvars file. See `variables.tf` for all options.

Common customizations:

```hcl
# Larger workers for production workloads
compute_machine_type = "m5.2xlarge"
worker_node_count    = 6

# Custom VPC CIDR (for peering/TGW integration)
vpc_cidr = "10.100.0.0/16"

# Transit Gateway egress (instead of NAT)
egress_type        = "tgw"
transit_gateway_id = "tgw-0123456789abcdef0"

# Enable Client VPN
create_client_vpn     = true
vpn_client_cidr_block = "10.200.0.0/22"
```

## Cluster Autoscaler

ROSA Classic supports cluster-wide autoscaling. Enable the cluster autoscaler to automatically adjust cluster size based on workload demands.

### Enable Autoscaler

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

### How It Works

| Component | Purpose |
|-----------|---------|
| **Cluster Autoscaler** | Controls cluster-wide scaling behavior (thresholds, timing, limits) |
| **Machine Pool Autoscaling** | Controls individual pool scaling (min/max replicas per pool) |

Both must be enabled for full autoscaling:
1. Enable `cluster_autoscaler_enabled = true` (cluster-wide settings)
2. Add machine pools with `autoscaling = { enabled = true, min = X, max = Y }`

### Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `autoscaler_max_nodes_total` | 100 | Maximum nodes cluster can scale to |
| `autoscaler_scale_down_enabled` | true | Allow scale down of idle nodes |
| `autoscaler_scale_down_utilization_threshold` | 0.5 | Scale down if utilization < 50% |
| `autoscaler_scale_down_delay_after_add` | 10m | Wait time after scale up |
| `autoscaler_scale_down_unneeded_time` | 10m | How long node must be idle |

### Example: Production with Autoscaling

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

See [docs/MACHINE-POOLS.md](../../docs/MACHINE-POOLS.md) for more machine pool examples.

## Destroying Clusters

```bash
# Destroy dev cluster
terraform destroy -var-file=dev.tfvars

# Destroy prod cluster (be careful!)
terraform destroy -var-file=prod.tfvars
```

**Note:** Cluster destruction takes 15-30 minutes. The ROSA API must fully process the deletion before IAM roles can be removed.
