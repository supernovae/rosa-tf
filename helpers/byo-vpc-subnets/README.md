# BYO-VPC Subnet Helper

Creates subnets, route tables, and routes inside an existing VPC for an additional ROSA cluster. This is a **standalone helper** that is not wired into any environment module -- run it manually, then copy the output subnet IDs into your cluster's BYO-VPC tfvars.

## When to Use This

- You want to deploy a second (or third) ROSA cluster into the same VPC
- You don't want to manually run AWS CLI commands to create subnets
- You want Terraform-managed, reproducible subnet creation with proper tags

## How It Works

```
Step 1: Deploy first cluster          Step 2: Create subnets           Step 3: Deploy second cluster
─────────────────────────             ────────────────────              ──────────────────────────────
environments/commercial-hcp/          helpers/byo-vpc-subnets/         environments/commercial-hcp/
terraform apply                       terraform apply                  terraform apply
  → Creates VPC + subnets               → Creates new subnets            → Uses existing VPC + new subnets
  → Output: vpc_id, subnet IDs          → Reuses parent NAT              → Non-overlapping pod/service CIDRs
                                        → Output: new subnet IDs
```

## Quick Start

### 1. Get the VPC ID from your first cluster

```bash
cd environments/commercial-hcp
terraform output vpc_id
# "vpc-0abc123def456"
```

### 2. Create the subnets (use a workspace per target)

```bash
cd helpers/byo-vpc-subnets
terraform init

# Create a workspace for this target (important if you use the helper
# for multiple clusters or across different AWS accounts/regions)
terraform workspace new my-cluster-2

# Copy and customize the example
cp examples/lab.tfvars my-lab.tfvars
# Edit my-lab.tfvars: set vpc_id, aws_region, cluster_name, CIDRs

terraform apply -var-file=my-lab.tfvars
```

### 3. Copy the outputs into your cluster tfvars

The `usage_instructions` output prints a ready-to-paste snippet:

```
existing_vpc_id             = "vpc-0abc123def456"
existing_private_subnet_ids = ["subnet-aaa111", "subnet-bbb222", "subnet-ccc333"]

pod_cidr     = "10.132.0.0/14"
service_cidr = "172.31.0.0/16"
```

### 4. Deploy the second cluster (separate workspace required)

```bash
cd environments/commercial-hcp
terraform workspace new cluster-2
terraform apply -var-file=cluster2.tfvars
```

## Egress Modes

| Mode | Default | What It Does |
|------|:-------:|-------------|
| `nat` | Yes | Looks up the parent VPC's existing NAT gateway and routes through it. Zero extra cost. |
| `tgw` | No | Routes via Transit Gateway. For GovCloud or hub-spoke topologies. Requires `transit_gateway_id`. |

### NAT Mode (default)

Reuses the parent VPC's NAT gateway. The helper finds it via `data.aws_nat_gateway` and points the new route tables at it.

```hcl
egress_type = "nat"   # default
```

### TGW Mode

For GovCloud or environments where egress goes through a Transit Gateway:

```hcl
egress_type        = "tgw"
transit_gateway_id = "tgw-0123456789abcdef0"
```

## CIDR Planning

The first cluster (with default VPC CIDR `10.0.0.0/16`) typically uses these subnet ranges:

| Subnet | CIDR Range |
|--------|-----------|
| Private (AZ-a) | `10.0.0.0/20` |
| Private (AZ-b) | `10.0.16.0/20` |
| Private (AZ-c) | `10.0.32.0/20` |
| Public (AZ-a) | `10.0.48.0/20` |
| Public (AZ-b) | `10.0.64.0/20` |
| Public (AZ-c) | `10.0.80.0/20` |

For the second cluster, use the next available blocks:

| Subnet | CIDR Range |
|--------|-----------|
| Private (AZ-a) | `10.0.96.0/20` |
| Private (AZ-b) | `10.0.112.0/20` |
| Private (AZ-c) | `10.0.128.0/20` |

See [docs/BYO-VPC.md](../../docs/BYO-VPC.md) for the full CIDR planning guide including pod and service CIDRs.

## Single-AZ vs Multi-AZ

Provide 1 AZ for dev/test or 3 AZs for production HA:

```hcl
# Single-AZ (dev/test)
availability_zones   = ["us-east-1a"]
private_subnet_cidrs = ["10.0.96.0/20"]

# Multi-AZ (production)
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs = ["10.0.96.0/20", "10.0.112.0/20", "10.0.128.0/20"]
```

## Workspaces

Use a **separate workspace** for each target when using this helper for multiple clusters or across different AWS accounts/regions:

```bash
cd helpers/byo-vpc-subnets

# Commercial us-east-1 subnets
terraform workspace new commercial-prod
terraform apply -var-file=examples/commercial-prod.tfvars

# GovCloud us-gov-west-1 subnets (different AWS creds)
terraform workspace new govcloud-lab
terraform apply -var-file=examples/govcloud-lab.tfvars
```

**Why this matters:** Without separate workspaces, the state file from a previous run persists. If you switch AWS accounts or regions, Terraform tries to refresh the old resources with the new credentials and fails with 401 auth errors.

Similarly, each **cluster** in `environments/` needs its own workspace:

```bash
cd environments/commercial-classic
terraform workspace new cluster-2
terraform apply -var-file=cluster2.tfvars
```

Without a separate workspace, Terraform sees the existing VPC in state from cluster-1 and tries to destroy it (count 1 -> 0) while the BYO-VPC locals still reference it, causing a dependency cycle.

## Destroy Order

Destroy in **reverse order** of creation:

```bash
# 1. Destroy the BYO-VPC cluster
cd environments/commercial-classic
terraform workspace select cluster-2
terraform destroy -var-file=cluster2.tfvars

# 2. Destroy the helper subnets
cd helpers/byo-vpc-subnets
terraform workspace select commercial-prod
terraform destroy -var-file=examples/commercial-prod.tfvars

# 3. Destroy the VPC-owning cluster LAST
cd environments/commercial-classic
terraform workspace select default
terraform destroy -var-file=cluster1.tfvars
```

If you destroy the VPC-owning cluster first, the VPC is deleted and remaining clusters/subnets lose networking and won't destroy cleanly.

After cleanup, delete empty workspaces:

```bash
terraform workspace select default
terraform workspace delete cluster-2
```

## What This Does NOT Do

- Modify the existing VPC in any way
- Create a new NAT gateway or Internet Gateway (reuses existing)
- Manage the ROSA cluster (that stays in `environments/`)
- Wire into any environment module (completely standalone)
