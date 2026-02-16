# ROSA HCP - AWS Commercial

Deploy Red Hat OpenShift Service on AWS with Hosted Control Planes (HCP) in AWS Commercial regions.

## Overview

ROSA HCP provides a fully managed OpenShift control plane, hosted in Red Hat's AWS infrastructure. This results in:

- **Faster provisioning**: ~15 minutes vs 40+ for Classic
- **Lower baseline cost**: No control plane nodes in your account
- **Automatic updates**: Control plane managed by Red Hat
- **Separate billing**: Control plane and machine pools billed separately

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    Red Hat's AWS Account                      │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                 Hosted Control Plane                    │  │
│  │  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌─────────────┐   │  │
│  │  │   API   │ │  etcd   │ │ Scheduler│ │ Controllers │   │  │
│  │  └─────────┘ └─────────┘ └──────────┘ └─────────────┘   │  │
│  └────────────────────────────┬────────────────────────────┘  │
└───────────────────────────────┼───────────────────────────────┘
                                │ AWS PrivateLink
┌───────────────────────────────┼───────────────────────────────┐
│                     Your AWS Account                          │
│  ┌────────────────────────────┴────────────────────────────┐  │
│  │                    Private Subnets                      │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │  │
│  │  │  Worker  │  │  Worker  │  │  Worker  │ Machine Pools │  │
│  │  │   Node   │  │   Node   │  │   Node   │               │  │
│  │  └──────────┘  └──────────┘  └──────────┘               │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

## Authentication

Commercial cloud uses **RHCS service account** authentication (client ID + client secret). The offline OCM token is deprecated for commercial environments.

### Setup

1. Go to [console.redhat.com/iam/service-accounts](https://console.redhat.com/iam/service-accounts)
2. Click **Create service account**
3. Give it a descriptive name (e.g., `rosa-terraform-automation`)
4. **Save the client ID and client secret immediately** -- the secret is only shown once
5. Go to [console.redhat.com/iam/user-access/users](https://console.redhat.com/iam/user-access/users)
6. Find the service account and assign it **OpenShift Cluster Manager** permissions

### Usage

```bash
# Set credentials (recommended: environment variables)
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"
```

This approach works for both **local workstation** use and **CI/CD pipelines** (GitHub Actions, Jenkins, etc.) since service accounts don't expire like offline tokens.

> **GovCloud Note:** GovCloud environments continue to use the offline OCM token from `console.openshiftusgov.com`. Service account authentication is for commercial cloud only.

## Quick Start

```bash
# Set RHCS credentials (see Authentication above)
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"

# Initialize Terraform
terraform init

# Development (single-AZ, public, minimal)
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"

# Production (multi-AZ, private, encrypted)
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```

## Configuration Options

### Development vs Production

| Feature | Development | Production |
|---------|-------------|------------|
| VPC Topology | Single-AZ | Multi-AZ |
| NAT Gateways | 1 | 3 (1 per AZ) |
| Cluster Access | Private (default) | Private |
| KMS Mode | `provider_managed` | `create` |
| etcd Encryption | No | Yes |
| Worker Nodes | 2 (default) | 2+ (scale as needed) |
| Autoscaling | Disabled | Enabled |
| Jump Host | No | Yes |
| Cost (est.) | ~$500/mo | ~$600+/mo |

> **Note:** HCP control plane is always multi-AZ (Red Hat managed). Worker count (default: 2) scales based on workload needs, not VPC topology.

### Security Features

| Feature | Dev Default | Prod Default | Notes |
|---------|-------------|--------------|-------|
| KMS Mode | `provider_managed` | `create` | See KMS section below |
| etcd Encryption | No | Yes | Requires custom KMS |
| Private Cluster | No | Yes | No public API endpoint |
| VPN Access | No | Optional | For private clusters |

### KMS Modes

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

# prod.tfvars - Customer-managed keys with etcd encryption
cluster_kms_mode = "create"
infra_kms_mode   = "create"
etcd_encryption  = true

# Bring your own keys
cluster_kms_mode    = "existing"
cluster_kms_key_arn = "arn:aws:kms:region:account:key/cluster-key-id"
infra_kms_mode      = "existing"
infra_kms_key_arn   = "arn:aws:kms:region:account:key/infra-key-id"
```

**Note:** `etcd_encryption` only applies when `cluster_kms_mode` is `create` or `existing`.

## Key Differences from Classic

| Feature | HCP | Classic |
|---------|-----|---------|
| Control Plane | Red Hat managed | Customer nodes |
| IAM Policies | AWS-managed | Customer-managed |
| Account Roles | 3 roles | 4 roles |
| Operator Roles | 8 roles | 6-7 roles |
| Provisioning Time | ~15 min | ~40 min |
| Subnets Required | Private only | Private + Public |
| Machine Pool Versions | n-2 drift limit | Independent |

## Machine Pools

HCP machine pools have specific requirements:

### Version Drift Constraint

Machine pools must be within **n-2 minor versions** of the control plane:

```
Control Plane: 4.16.x
Valid Pool Versions: 4.16.x, 4.15.x, 4.14.x
Invalid: 4.13.x (too old)
```

**Upgrade Sequence**: Always upgrade control plane **first**, then machine pools.

### Example Configurations

See [docs/MACHINE-POOLS.md](../../docs/MACHINE-POOLS.md) for comprehensive examples.

```hcl
machine_pools = [
  # GPU Machine Pool
  {
    name          = "gpu"
    instance_type = "g4dn.xlarge"
    replicas      = 1
    labels        = { "node-role.kubernetes.io/gpu" = "" }
    taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  },

  # High Memory Pool
  {
    name          = "highmem"
    instance_type = "r5.2xlarge"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/highmem" = "" }
  },

  # Autoscaling Pool
  {
    name        = "workers"
    instance_type = "m6i.xlarge"
    autoscaling = { enabled = true, min = 2, max = 10 }
  }
]
```

## Cluster Autoscaler

ROSA HCP supports cluster-wide autoscaling. The autoscaler is fully managed by Red Hat and runs with the hosted control plane.

### Enable Autoscaler

```hcl
# Enable cluster autoscaler
cluster_autoscaler_enabled = true
autoscaler_max_nodes_total = 50
```

### How It Works

| Component | Purpose |
|-----------|---------|
| **Cluster Autoscaler** | Controls cluster-wide scaling behavior (max nodes, timeouts) |
| **Machine Pool Autoscaling** | Controls individual pool scaling (min/max replicas per pool) |

Both must be enabled for full autoscaling:
1. Enable `cluster_autoscaler_enabled = true` (cluster-wide settings)
2. Add machine pools with `autoscaling = { enabled = true, min = X, max = Y }`

### Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `autoscaler_max_nodes_total` | 100 | Maximum nodes across autoscaling pools |
| `autoscaler_max_node_provision_time` | 25m | Time to wait for node ready |
| `autoscaler_max_pod_grace_period` | 600 | Pod termination grace (seconds) |
| `autoscaler_pod_priority_threshold` | -10 | Priority below which pods don't affect scaling |

### Example: Production with Autoscaling

```hcl
cluster_autoscaler_enabled = true
autoscaler_max_nodes_total = 100

machine_pools = [
  {
    name          = "workers"
    instance_type = "m6i.xlarge"
    autoscaling   = { enabled = true, min = 3, max = 20 }
  }
]
```

## Cluster Access

### Public Cluster (Dev)

```bash
# Get credentials
terraform output cluster_admin_password

# Login
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)
```

### Private Cluster (Prod)

For private clusters, use one of:

**Option 1: Jump Host with SSM**
```bash
# Connect to jump host
aws ssm start-session --target $(terraform output -raw jumphost_instance_id)

# From jump host
oc login <api_url> -u cluster-admin -p <password>
```

**Option 2: Client VPN**
```bash
# Download VPN config
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn

# Connect with OpenVPN client, then use oc login
```

## Cost Estimate (Default Configuration)

HCP control plane is managed by Red Hat - you only pay for worker nodes plus fees.

| Component | Base (2 workers) |
|-----------|------------------|
| EC2 Workers (2x m6i.xlarge) | ~$280/mo |
| OpenShift Fee (workers) | ~$250/mo |
| HCP Control Plane Fee | ~$180/mo |
| NAT Gateway | ~$32/mo |
| **Total Estimate** | **~$740/mo** |

*EC2: m6i.xlarge ~$140/mo. OpenShift fee ~$0.171/hr per 4 vCPUs. HCP CP fee ~$0.25/hr. Scales with workers.*

**Cost Savings Options:**
- **EC2 Reserved Instances**: Save up to 40-60% on worker EC2 costs with 1 or 3-year commitments
- **OpenShift 1-Year Commit**: Discounted hourly rate with annual commitment via AWS Marketplace
- **Red Hat Private Offer**: Contact your Red Hat seller for custom pricing up to 3 years

### Cost Optimization Tips

**Development:**
- Single AZ deployment (includes single NAT gateway)
- Public cluster (no VPN needed)
- `cluster_kms_mode = "provider_managed"` (AWS managed key, no extra cost)
- Minimal worker nodes (2)

**Production:**
- Enable autoscaling with appropriate min/max
- Spot instances for machine pools (coming soon)
- Right-size instance types
- Consider reserved instances for baseline capacity

## Customization

### Custom Variables

Create a custom `.tfvars` file:

```hcl
# custom.tfvars
cluster_name = "my-cluster"
aws_region   = "eu-west-1"

# Your specific configuration
multi_az           = true
worker_node_count  = 4
compute_machine_type = "m6i.2xlarge"
```

Apply:
```bash
terraform apply -var-file="custom.tfvars"
```

### Override Defaults

```bash
# Override specific variables
terraform apply -var-file="prod.tfvars" \
  -var="worker_node_count=5"

# For machine pools, edit tfvars directly (complex variable)
```

## Troubleshooting

### Version Drift Error

```
Error: Machine pool version 4.13.x is not compatible with control plane 4.16.x
```

**Solution**: Update machine pool version to within n-2 of control plane.

### OIDC Provider Issues

HCP uses managed OIDC. If you see OIDC errors:
1. Verify IAM roles exist
2. Check OIDC provider trust policy
3. Ensure operator role prefix matches cluster name

### Private Cluster Access

If unable to connect to private cluster:
1. Verify VPN connection or jump host access
2. Check security group allows traffic
3. Confirm DNS resolution works for cluster endpoints

## Related Documentation

- [ROSA HCP Overview](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/architecture/rosa-hcp)
- [AWS Managed Policies](https://docs.aws.amazon.com/rosa/latest/userguide/security-iam-awsmanpol.html)
- [HCP Machine Pools](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cluster_administration/rosa-managing-worker-nodes)
