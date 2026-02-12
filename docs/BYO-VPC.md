# BYO-VPC (Bring Your Own VPC)

Deploy ROSA clusters into an existing VPC instead of creating a new one.

## When to Use BYO-VPC

| Scenario | Use BYO-VPC? |
|----------|:------------:|
| First cluster in a new VPC | No (let Terraform create it) |
| Second cluster sharing an existing VPC | **Yes** |
| Pre-existing VPC from another team/account | **Yes** |
| VPC created by CloudFormation or another IaC tool | **Yes** |
| Testing multi-cluster workload isolation | **Yes** |

## Anti-Pattern Warning

> **Multi-cluster in a single VPC is a supported but discouraged pattern.**
>
> A VPC is a natural blast radius boundary. When multiple clusters share a VPC:
> - A misconfigured security group affects all clusters
> - A VPC-level issue (route table, NACL) impacts all clusters
> - Subnet IP exhaustion can prevent scaling any cluster
> - Terraform state for the VPC-owning cluster becomes a dependency for all
>
> **Recommendation:** Use separate VPCs per cluster for production. Reserve shared VPC for dev/test or when organizational constraints require it.

## How It Works

When `existing_vpc_id` is set:

1. **VPC creation is skipped** — `module.vpc` gets `count = 0`
2. **Data sources look up the existing VPC and subnets** — `data.aws_vpc.existing` and `data.aws_subnet.existing_private`
3. **A locals indirection layer** (`local.effective_*`) seamlessly switches between created and provided network resources
4. **All downstream modules** (cluster, ECR, security groups, jumphost, VPN) consume `local.effective_*` without knowing the source

```
┌─────────────────────────────────┐     ┌──────────────────────────────────┐
│  Mode: Create VPC (default)     │     │  Mode: BYO-VPC                   │
│                                 │     │                                  │
│  module.vpc creates:            │     │  existing_vpc_id = "vpc-..."     │
│    - VPC + subnets              │     │  existing_private_subnet_ids     │
│    - NAT/TGW                    │     │  existing_public_subnet_ids      │
│    - Route tables               │     │                                  │
└──────────────┬──────────────────┘     └───────────────┬──────────────────┘
               │                                        │
               └────────────┬───────────────────────────┘
                            │
                   local.effective_vpc_id
                   local.effective_private_subnet_ids
                   local.effective_public_subnet_ids
                   local.effective_availability_zones
                            │
               ┌────────────┼────────────────────┐
               │            │                    │
          module.rosa   module.ecr        module.jumphost
          module.sg     module.vpn        ...
```

## AZ Topology Inference

The number of private subnets determines the cluster topology:

| Private Subnets | Topology | Use Case |
|:-:|---|---|
| 1 | Single-AZ | Dev/test, cost optimization |
| 3 | Multi-AZ | Production, high availability |

In BYO-VPC mode, the `multi_az` variable is ignored — topology is inferred from the subnets you provide. The actual availability zones are looked up from the subnets via `data.aws_subnet`.

## CIDR Planning Guide

### Default CIDRs

| CIDR Type | Default Value | Purpose |
|-----------|:------------:|---------|
| Machine (VPC) | `10.0.0.0/16` | Node IPs, allocated from VPC subnets |
| Pod | `10.128.0.0/14` | Pod network overlay |
| Service | `172.30.0.0/16` | ClusterIP services |

### Multi-Cluster CIDR Plan

Each cluster in the same VPC needs **unique pod and service CIDRs**. Machine CIDR is shared (it's the VPC CIDR), but each cluster uses different subnets within it.

```
VPC CIDR: 10.0.0.0/16 (shared)

Cluster 1 (default):
  Subnets:     10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  Pod CIDR:    10.128.0.0/14  (default)
  Service CIDR: 172.30.0.0/16 (default)

Cluster 2:
  Subnets:     10.0.48.0/20, 10.0.64.0/20, 10.0.80.0/20
  Pod CIDR:    10.132.0.0/14
  Service CIDR: 172.31.0.0/16

Cluster 3:
  Subnets:     10.0.96.0/20, 10.0.112.0/20, 10.0.128.0/20
  Pod CIDR:    10.136.0.0/14
  Service CIDR: 172.28.0.0/16
```

### Available Pod CIDR Blocks (/14)

Starting from the default `10.128.0.0/14`:

| Cluster | Pod CIDR | IP Range |
|---------|----------|----------|
| 1 | `10.128.0.0/14` | 10.128.0.0 – 10.131.255.255 |
| 2 | `10.132.0.0/14` | 10.132.0.0 – 10.135.255.255 |
| 3 | `10.136.0.0/14` | 10.136.0.0 – 10.139.255.255 |
| 4 | `10.140.0.0/14` | 10.140.0.0 – 10.143.255.255 |

### Available Service CIDR Blocks (/16)

Starting from the default `172.30.0.0/16`:

| Cluster | Service CIDR | IP Range |
|---------|-------------|----------|
| 1 | `172.30.0.0/16` | 172.30.0.0 – 172.30.255.255 |
| 2 | `172.31.0.0/16` | 172.31.0.0 – 172.31.255.255 |
| 3 | `172.28.0.0/16` | 172.28.0.0 – 172.28.255.255 |
| 4 | `172.29.0.0/16` | 172.29.0.0 – 172.29.255.255 |

## Step-by-Step: Multi-Cluster in Single VPC

### Step 1: Deploy the First Cluster (VPC Owner)

Use the default configuration — Terraform creates the VPC:

```hcl
# environments/commercial-hcp/cluster1.tfvars
cluster_name = "cluster-1"
aws_region   = "us-east-1"
vpc_cidr     = "10.0.0.0/16"
multi_az     = true
# ... standard config ...
```

```bash
cd environments/commercial-hcp
terraform init
terraform apply -var-file="cluster1.tfvars"
```

### Step 2: Capture VPC Outputs

```bash
terraform output vpc_id
# "vpc-0abc123def456"

terraform output private_subnet_ids
# ["subnet-aaa111", "subnet-bbb222", "subnet-ccc333"]

terraform output public_subnet_ids
# ["subnet-ddd444", "subnet-eee555", "subnet-fff666"]
```

### Step 3: Deploy the Second Cluster (BYO-VPC)

Create a **separate Terraform workspace** for the second cluster. This is required -- see [Terraform Workspaces](#terraform-workspaces-required) for why.

```hcl
# environments/commercial-hcp/cluster2.tfvars
cluster_name = "cluster-2"
aws_region   = "us-east-1"

# BYO-VPC: point to existing VPC
existing_vpc_id             = "vpc-0abc123def456"
existing_private_subnet_ids = ["subnet-aaa111", "subnet-bbb222", "subnet-ccc333"]
# existing_public_subnet_ids = ["subnet-ddd444", "subnet-eee555", "subnet-fff666"]  # if public

# Non-overlapping CIDRs
pod_cidr     = "10.132.0.0/14"
service_cidr = "172.31.0.0/16"

# ... standard config ...
```

```bash
terraform workspace new cluster-2
terraform apply -var-file="cluster2.tfvars"
```

### Step 4: Verify

After deployment, verify CIDR isolation:

```bash
# On cluster-2:
oc get network.config cluster -o jsonpath='{.spec.clusterNetwork[0].cidr}'
# Should show: 10.132.0.0/14

oc get network.config cluster -o jsonpath='{.spec.serviceNetwork[0]}'
# Should show: 172.31.0.0/16
```

## Step-by-Step: BYO-VPC from External Source

If the VPC was created outside of this Terraform module (e.g., by another team, CloudFormation, or manual setup):

### VPC Requirements

The existing VPC must have:

- [x] **DNS hostnames enabled** (`enable_dns_hostnames = true`)
- [x] **DNS resolution enabled** (`enable_dns_support = true`)
- [x] **Private subnets** with routes to a NAT Gateway, Transit Gateway, or proxy (for ROSA to reach Red Hat APIs)
- [x] **Subnet tags:**
  - Private subnets: `kubernetes.io/role/internal-elb = 1`
  - Public subnets (if used): `kubernetes.io/role/elb = 1`

### Configuration

```hcl
existing_vpc_id             = "vpc-from-other-team"
existing_private_subnet_ids = ["subnet-priv-1", "subnet-priv-2", "subnet-priv-3"]
existing_public_subnet_ids  = ["subnet-pub-1", "subnet-pub-2", "subnet-pub-3"]

# Use defaults if this is the only ROSA cluster in the VPC
# pod_cidr     = "10.128.0.0/14"   # default
# service_cidr = "172.30.0.0/16"   # default
```

## Validation

The module includes built-in validation:

| Check | Error Message |
|-------|--------------|
| Private subnets required with BYO-VPC | `existing_private_subnet_ids is required when existing_vpc_id is set.` |
| Subnet count must be 1 or 3 | `Provide 1 subnet (single-AZ) or 3 subnets (multi-AZ).` |
| Public/private subnet count mismatch | `existing_public_subnet_ids must have the same count as existing_private_subnet_ids.` |
| Public cluster needs public subnets | `Public clusters require existing_public_subnet_ids when using BYO-VPC.` |

## Outputs in BYO-VPC Mode

When using BYO-VPC, some outputs change:

| Output | BYO-VPC Value |
|--------|--------------|
| `byo_vpc` | `true` |
| `egress_type` | `"byo-vpc"` |
| `nat_gateway_ips` | `[]` (not managed) |
| `vpc_flow_logs_enabled` | `false` (not managed) |
| `private_route_table_ids` | `[]` (not managed) |

## Terraform Workspaces (Required)

Each cluster **must** use its own Terraform workspace (or separate state directory). This is not optional -- attempting to switch an existing cluster from VPC-creating mode to BYO-VPC mode within the same state will cause dependency cycles.

### Why Workspaces Are Required

When `existing_vpc_id` is set, the VPC module gets `count = 0`. If the same state previously had `count = 1` (a created VPC), Terraform tries to destroy the VPC while simultaneously referencing it through `local.effective_*` locals, creating a circular dependency graph.

Separate workspaces avoid this entirely -- each cluster starts with a clean state.

### Workspace Setup

```bash
cd environments/commercial-classic   # or any environment

# First cluster: uses the default workspace
terraform init
terraform apply -var-file=cluster1.tfvars

# Second cluster: create a new workspace
terraform workspace new cluster-2
terraform apply -var-file=cluster2.tfvars

# Third cluster:
terraform workspace new cluster-3
terraform apply -var-file=cluster3.tfvars
```

### Switching Between Clusters

```bash
# List workspaces
terraform workspace list
#   default        (cluster-1, owns the VPC)
# * cluster-2
#   cluster-3

# Switch to cluster-1
terraform workspace select default

# Switch to cluster-2
terraform workspace select cluster-2
```

### Subnet Helper Workspaces

If you use `helpers/byo-vpc-subnets/` to create subnets for multiple clusters or across different AWS accounts/regions, use a workspace per target:

```bash
cd helpers/byo-vpc-subnets

# Commercial subnets
terraform workspace new commercial
terraform apply -var-file=examples/commercial-prod.tfvars

# GovCloud subnets (different AWS credentials + region)
terraform workspace select default   # or: terraform workspace new govcloud
terraform apply -var-file=examples/govcloud-lab.tfvars
```

This prevents state conflicts when the same helper directory is used for different accounts or regions. Without separate workspaces, Terraform will try to refresh resources from a previous run using the wrong credentials (e.g., commercial creds against GovCloud resources), causing 401 auth errors.

## Destroy Order

When tearing down a multi-cluster VPC setup, **order matters**. Destroy in reverse order of creation:

```bash
# Step 1: Destroy BYO-VPC clusters (newest first)
cd environments/commercial-classic
terraform workspace select cluster-3
terraform destroy -var-file=cluster3.tfvars

terraform workspace select cluster-2
terraform destroy -var-file=cluster2.tfvars

# Step 2: Destroy subnet helper resources (if used)
cd helpers/byo-vpc-subnets
terraform workspace select commercial
terraform destroy -var-file=examples/commercial-prod.tfvars

# Step 3: Destroy the VPC-owning cluster LAST
cd environments/commercial-classic
terraform workspace select default
terraform destroy -var-file=cluster1.tfvars
```

**Why this order?**

| Step | What | Why |
|------|------|-----|
| 1 | BYO-VPC clusters | They reference subnets/VPC they don't own |
| 2 | Helper subnets | They reference the VPC's NAT gateway and S3 endpoint |
| 3 | First cluster (VPC owner) | Deletes VPC, subnets, NAT, IGW -- everything |

If you destroy the VPC-owning cluster first, the VPC is deleted and remaining clusters lose all networking. The BYO-VPC clusters will then fail to destroy cleanly because their subnets no longer exist.

Workspaces make this safer because each cluster's state is isolated -- destroying one workspace cannot accidentally affect another.

### Cleaning Up Workspaces

After destroying all resources in a workspace:

```bash
terraform workspace select default
terraform workspace delete cluster-2
terraform workspace delete cluster-3
```

## Environments

BYO-VPC is supported across all environments:

| Environment | BYO-VPC | Notes |
|-------------|:-------:|-------|
| commercial-hcp | Yes | Full support including public clusters |
| commercial-classic | Yes | Full support including public clusters |
| govcloud-hcp | Yes | Always private (no public subnet validation) |
| govcloud-classic | Yes | Always private (no public subnet validation) |
