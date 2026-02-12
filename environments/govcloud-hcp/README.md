# ROSA HCP - AWS GovCloud

Deploy Red Hat OpenShift Service on AWS with Hosted Control Planes (HCP) in AWS GovCloud for FedRAMP High workloads.

## Overview

ROSA HCP in GovCloud provides:

- **Hosted control plane**: Red Hat manages control plane in their FedRAMP-authorized environment
- **Faster provisioning**: ~15 minutes vs 40+ for Classic
- **AWS managed policies**: Automatically updated by AWS in the aws-us-gov partition
- **FedRAMP compliance**: FIPS, private cluster, KMS encryption enforced

## GovCloud Enforcement

The following security controls are **MANDATORY** and cannot be disabled:

| Control | Value | Notes |
|---------|-------|-------|
| FIPS Mode | Enabled | Cryptographic compliance |
| Cluster Access | Private Only | No public API endpoint |
| etcd Encryption | Enabled | KMS required |
| EBS Encryption | Enabled | KMS required |
| API Endpoint | api.openshiftusgov.com | FedRAMP authorized |

## VPC and Cluster Topology

Each GovCloud HCP cluster should be deployed into **its own dedicated VPC**. While the BYO-VPC variables (`existing_vpc_id`, `existing_private_subnet_ids`) are available in this environment for flexibility, deploying multiple ROSA clusters into a single VPC in GovCloud is **not recommended and not currently validated**.

ROSA clusters create PrivateLink endpoint services, internal load balancers, and security groups that are tightly coupled to the VPC. When a cluster is destroyed, these resources may not be fully cleaned up, requiring manual intervention to remove orphaned NLBs, VPC endpoint services, and ENIs before subnets or the VPC can be deleted. This teardown complexity multiplies with each additional cluster in the VPC.

**Guidance:**

- **One VPC per cluster** is the supported and tested pattern for GovCloud HCP
- Use separate Terraform workspaces to manage multiple clusters independently
- If you have a use case that requires shared networking, consider VPC peering or Transit Gateway to connect independent cluster VPCs
- For multi-cluster in a single VPC scenarios, see [BYO-VPC.md](../../docs/BYO-VPC.md) for general documentation, but be aware that GovCloud teardown has additional manual cleanup steps

## Quick Start

```bash
# Set GovCloud credentials
export AWS_REGION=us-gov-west-1
export AWS_DEFAULT_REGION=$AWS_REGION

# Get token from FedRAMP console
export TF_VAR_ocm_token="your-token-from-console.openshiftusgov.com"

# Initialize
cd environments/govcloud-hcp
terraform init

# Development (single-AZ, cost-optimized)
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"

# Production (multi-AZ, HA)
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```

## Development vs Production

| Aspect | Development | Production |
|--------|-------------|------------|
| VPC Topology | Single-AZ | Multi-AZ |
| NAT Gateways | 1 | 3 |
| Worker Nodes | 3 (default) | 3+ (scale as needed) |
| Autoscaling | Optional | Recommended |
| Jump Host | Yes | Yes |
| Client VPN | Optional | Recommended |

> **Note:** HCP control plane is always multi-AZ (Red Hat managed). Worker count (default: 2) scales based on workload needs, not VPC topology.

**Security is identical** - both environments enforce FIPS, private cluster, and KMS encryption.

### Cost Estimate (Default Configuration)

HCP control plane is managed by Red Hat - you only pay for worker nodes plus fees.

| Component | Base (2 workers) |
|-----------|------------------|
| EC2 Workers (2x m5.xlarge) | ~$320/mo |
| OpenShift Fee (workers) | ~$250/mo |
| HCP Control Plane Fee | ~$180/mo |
| NAT Gateway | ~$36/mo |
| Jump Host (t3.micro) | ~$12/mo |
| **Total Estimate** | **~$800/mo** |

*GovCloud EC2 ~10-15% higher. OpenShift fee ~$0.171/hr per 4 vCPUs. HCP CP fee ~$0.25/hr. Spot instances coming soon.*

**Cost Savings Options:**
- **EC2 Reserved Instances**: Save up to 40-60% on worker EC2 costs with 1 or 3-year commitments
- **OpenShift 1-Year Commit**: Discounted hourly rate with annual commitment via AWS Marketplace
- **Red Hat Private Offer**: Contact your Red Hat seller for custom pricing up to 3 years

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│               Red Hat's FedRAMP Environment                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │           Hosted Control Plane (FIPS Compliant)         │  │
│  │  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌─────────────┐   │  │
│  │  │   API   │ │  etcd   │ │ Scheduler│ │ Controllers │   │  │
│  │  │  (KMS)  │ │  (KMS)  │ │          │ │             │   │  │
│  │  └─────────┘ └─────────┘ └──────────┘ └─────────────┘   │  │
│  └────────────────────────────┬────────────────────────────┘  │
└───────────────────────────────┼───────────────────────────────┘
                                │ AWS PrivateLink
┌───────────────────────────────┼───────────────────────────────┐
│          Your AWS GovCloud Account (aws-us-gov)               │
│  ┌────────────────────────────┴────────────────────────────┐  │
│  │                    Private Subnets                      │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │  │
│  │  │  Worker  │  │  Worker  │  │  Worker  │ FIPS Enabled  │  │
│  │  │  (KMS)   │  │  (KMS)   │  │  (KMS)   │ EBS Encrypted │  │
│  │  └──────────┘  └──────────┘  └──────────┘               │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌──────────────┐       ┌─────────────────┐                   │
│  │  Jump Host   │       │    KMS Keys     │                   │
│  │    (SSM)     │       │  • Cluster      │                   │
│  └──────────────┘       │  • Infra        │                   │
│                         └─────────────────┘                   │
└───────────────────────────────────────────────────────────────┘
```

## Cluster Access

All GovCloud HCP clusters are **private only**. Access methods:

### Option 1: SSM Jump Host (Recommended)

```bash
# Connect to jump host
aws ssm start-session --target $(terraform output -raw jumphost_instance_id) --region us-gov-west-1

# From jump host, login to cluster
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)
```

### Option 2: Client VPN

The client-vpn module generates certificates automatically - no ACM setup required.

```bash
# Enable VPN in tfvars
create_client_vpn = true

# Apply (takes 15-20 minutes)
terraform apply -var-file=prod.tfvars

# Download config (includes auto-generated certs)
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn

# Connect with OpenVPN
sudo openvpn --config vpn-config.ovpn
```

**Cost:** ~$116/month. Consider using jump host (SSM) for cost savings.

## Machine Pools

HCP machine pools have version constraints. See [docs/MACHINE-POOLS.md](../../docs/MACHINE-POOLS.md) for comprehensive guidance.

### Version Drift Rule

Machine pools must be within **n-2** of control plane:

```
Control Plane: 4.18.x
Valid: 4.18.x, 4.17.x, 4.16.x
Invalid: 4.15.x
```

**Always upgrade control plane first, then machine pools.**

### Example Configurations

```hcl
machine_pools = [
  # Additional workers with autoscaling
  {
    name          = "workers"
    instance_type = "m5.xlarge"
    autoscaling   = { enabled = true, min = 2, max = 10 }
  },
  
  # GPU for ML/AI (check GovCloud availability)
  {
    name          = "gpu"
    instance_type = "p3.2xlarge"
    replicas      = 1
    labels        = { "node-role.kubernetes.io/gpu" = "" }
    taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  },
  
  # High memory for data workloads
  {
    name          = "highmem"
    instance_type = "r5.2xlarge"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/highmem" = "" }
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
    instance_type = "m5.xlarge"
    autoscaling   = { enabled = true, min = 3, max = 20 }
  }
]
```

## KMS Encryption (Mandatory)

KMS encryption is **mandatory** in GovCloud for FedRAMP compliance (SC-12/SC-13 controls).

### KMS Modes

GovCloud only supports two modes (`provider_managed` is NOT available):

| Mode | Description | Use Case |
|------|-------------|----------|
| `create` (DEFAULT) | Terraform creates customer-managed key | Most deployments |
| `existing` | Use your own KMS key ARN | Centralized key management |

Two separate KMS modes for blast radius containment:
- `cluster_kms_mode` - For ROSA workers and etcd
- `infra_kms_mode` - For jump host, CloudWatch, S3, VPN

```hcl
# Default - Terraform manages the keys
cluster_kms_mode = "create"
infra_kms_mode   = "create"

# Bring your own keys (must have proper policies)
cluster_kms_mode    = "existing"
cluster_kms_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/cluster-key..."
infra_kms_mode      = "existing"
infra_kms_key_arn   = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/infra-key..."
```

### FedRAMP Requirement

> "The system owner generates, controls, rotates, and can revoke cryptographic keys used to protect customer data."

This is why `provider_managed` (AWS managed `aws/ebs` key) is not available in GovCloud - FedRAMP requires customer control over cryptographic keys.

### Key Features

When `cluster_kms_mode = "create"` or `infra_kms_mode = "create"`:
- Automatic key rotation enabled
- 30-day deletion protection (configurable)
- Proper IAM policies for ROSA roles
- Separate keys for cluster and infrastructure (blast radius containment)

## Comparison: GovCloud vs Commercial HCP

| Feature | GovCloud | Commercial |
|---------|----------|------------|
| FIPS | Required | Optional |
| Private Cluster | Required | Optional |
| KMS Encryption | Required | Optional |
| API Endpoint | api.openshiftusgov.com | api.openshift.com |
| Partition | aws-us-gov | aws |
| Policy Type | AWS Managed | AWS Managed |

## Compliance

This environment is designed for:

- **FedRAMP High**: FIPS 140-2, encryption at rest
- **ITAR/EAR**: GovCloud data residency
- **DoD IL2-IL5**: With appropriate controls
- **NIST 800-53**: Security controls mapped

## Troubleshooting

### Partition Error

```
Error: This environment is designed for AWS GovCloud (aws-us-gov partition)
```

Ensure AWS credentials are for GovCloud:
```bash
aws sts get-caller-identity
# Should show aws-us-gov partition
```

### Token Issues

```
Error: invalid_grant: Invalid refresh token
```

Get fresh token from: https://console.openshiftusgov.com/openshift/token

### Version Drift

```
Warning: Machine pool version drift detected
```

Upgrade control plane first, then machine pools. Set `skip_version_drift_check = true` temporarily during upgrades if needed.

## Related Documentation

- [ROSA GovCloud Documentation](https://cloud.redhat.com/experts/rosa/rosa-govcloud/)
- [FedRAMP Hybrid Cloud Console](https://console.openshiftusgov.com)
- [AWS GovCloud Managed Policies](https://docs.aws.amazon.com/rosa/latest/userguide/security-iam-awsmanpol.html)
- [HCP Machine Pools](modules/cluster/machine-pools-hcp/README.md)
