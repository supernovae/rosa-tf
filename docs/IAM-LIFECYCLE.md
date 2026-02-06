# IAM Role Lifecycle Management

This document describes the IAM role architecture and lifecycle management for ROSA Classic and ROSA HCP clusters.

## Overview

ROSA Classic and ROSA HCP use different IAM role architectures:

| Aspect | ROSA Classic | ROSA HCP |
|--------|--------------|----------|
| Account Roles | Cluster-scoped | Account-level (shared) |
| Operator Roles | Per-cluster | Per-cluster |
| Default Prefix | cluster_name | ManagedOpenShift |
| Deletion Behavior | Removed with cluster | Persist independently |

## Architecture Diagrams

### ROSA Classic - Cluster-Scoped Roles

Each Classic cluster owns its own IAM roles. Destroying a cluster cleanly removes its roles without affecting other clusters.

```
Cluster A                           Cluster B
    |                                   |
    +---> cluster-a-Installer-Role      +---> cluster-b-Installer-Role
    +---> cluster-a-Support-Role        +---> cluster-b-Support-Role
    +---> cluster-a-ControlPlane-Role   +---> cluster-b-ControlPlane-Role
    +---> cluster-a-Worker-Role         +---> cluster-b-Worker-Role
    +---> cluster-a-operator-roles      +---> cluster-b-operator-roles
```

### ROSA HCP - Account + Cluster Layers

HCP uses a two-layer architecture:

1. **Account Layer (shared)**: Account roles shared across all HCP clusters
2. **Cluster Layer (per-cluster)**: Operator roles and OIDC config per cluster

```
Account Layer (deploy once)
    |
    +---> ManagedOpenShift-HCP-ROSA-Installer-Role  (shared)
    +---> ManagedOpenShift-HCP-ROSA-Support-Role    (shared)
    +---> ManagedOpenShift-HCP-ROSA-Worker-Role     (shared)
    
Cluster Layer (deploy per cluster)
    |
    +---> HCP Cluster A
    |       +---> cluster-a-operator-roles
    |       +---> cluster-a-oidc-config
    |
    +---> HCP Cluster B
            +---> cluster-b-operator-roles
            +---> cluster-b-oidc-config
```

## ROSA Classic Configuration

### Default Behavior (Cluster-Scoped)

By default, Classic clusters use the cluster name as the role prefix:

```hcl
# environments/commercial-classic/dev.tfvars
cluster_name = "my-cluster"
# Roles created: my-cluster-Installer-Role, my-cluster-Support-Role, etc.
```

### Destroying a Classic Cluster

When you destroy a Classic cluster, Terraform removes:
- All account roles (Installer, Support, ControlPlane, Worker)
- All operator roles
- OIDC configuration

This is the desired behavior - clean teardown without orphaned resources.

### Key Points

- Each cluster has its own roles
- Destroying cluster A does not affect cluster B
- No manual cleanup required

## ROSA HCP Configuration

### Single-Cluster Mode (Default)

For simple deployments with one cluster:

```hcl
# environments/commercial-hcp/dev.tfvars
create_account_roles = true  # Default
account_role_prefix  = "ManagedOpenShift"
```

Account roles are created with the cluster and destroyed when the cluster is destroyed.

### Multi-Cluster Mode (Recommended for Production)

For multiple HCP clusters sharing account roles:

**Step 1: Deploy Account Layer (once per AWS account)**

```bash
cd environments/account-hcp

# For Commercial AWS:
terraform apply -var-file="commercial.tfvars"

# For AWS GovCloud:
terraform apply -var-file="govcloud.tfvars"
```

This creates shared account roles:
- ManagedOpenShift-HCP-ROSA-Installer-Role
- ManagedOpenShift-HCP-ROSA-Support-Role
- ManagedOpenShift-HCP-ROSA-Worker-Role

**Step 2: Deploy Clusters (referencing shared roles)**

```hcl
# environments/commercial-hcp/cluster-a.tfvars
create_account_roles = false  # Don't create, discover existing
account_role_prefix  = "ManagedOpenShift"
cluster_name         = "cluster-a"
```

```bash
terraform apply -var-file="cluster-a.tfvars"
terraform apply -var-file="cluster-b.tfvars"
# Both clusters discover and use the shared ManagedOpenShift-* roles
```

**Step 3: Manage Lifecycle Independently**

- Clusters can be created/destroyed without affecting account roles
- Account roles persist until explicitly destroyed via account layer
- Upgrade account roles independently:
  ```bash
  cd environments/account-hcp
  terraform apply  # Updates role policies
  ```

### Role Discovery

When `create_account_roles = false`, the module auto-discovers roles by naming convention:

```
{account_role_prefix}-HCP-ROSA-Installer-Role
{account_role_prefix}-HCP-ROSA-Support-Role
{account_role_prefix}-HCP-ROSA-Worker-Role
```

Default prefix `ManagedOpenShift` matches the ROSA CLI, enabling interoperability:

```bash
# Roles created via ROSA CLI work with Terraform
rosa create account-roles --hosted-cp --prefix ManagedOpenShift

# Roles created via Terraform work with ROSA CLI
rosa create cluster --hosted-cp --role-arn ...
```

### Explicit ARN Override

You can bypass discovery and provide explicit ARNs:

```hcl
create_account_roles = false
installer_role_arn   = "arn:aws:iam::123456789012:role/Custom-Installer-Role"
support_role_arn     = "arn:aws:iam::123456789012:role/Custom-Support-Role"
worker_role_arn      = "arn:aws:iam::123456789012:role/Custom-Worker-Role"
```

### Error Handling

If roles are not found, you get a helpful error:

```
Error: HCP account roles not found.

Expected roles (with prefix "ManagedOpenShift"):
  - ManagedOpenShift-HCP-ROSA-Installer-Role
  - ManagedOpenShift-HCP-ROSA-Support-Role
  - ManagedOpenShift-HCP-ROSA-Worker-Role

To create shared account roles:
  Option 1 - Use ROSA CLI:
    rosa create account-roles --hosted-cp --prefix ManagedOpenShift

  Option 2 - Use Terraform account layer:
    cd environments/account-hcp && terraform apply
```

### Production Lifecycle Protection

**WARNING**: HCP account roles are shared by ALL clusters in the account. Accidentally destroying them will break all existing clusters.

Terraform's `prevent_destroy` lifecycle meta-argument cannot be set dynamically, so the module defaults to `prevent_destroy = false` to allow iteration during development.

**For production environments**, protect shared roles using one of these strategies:

**Option 1: Fork the module**
```hcl
# In your forked module's main.tf
lifecycle {
  prevent_destroy = true
}
```

**Option 2: Remove from state before destroy**
```bash
# Preserve account roles when destroying the account layer
terraform state rm module.rosa_hcp_account.aws_iam_role.account_role
terraform destroy  # Won't touch the roles
```

**Option 3: Separate state management**
```bash
# Import account roles into dedicated state
cd account-roles-state/
terraform import aws_iam_role.installer ManagedOpenShift-HCP-ROSA-Installer-Role
# Manage independently from cluster state
```

## ROSA CLI Interoperability

Both ROSA Classic and HCP support interoperability with the ROSA CLI:

### Creating Roles via ROSA CLI

```bash
# Classic
rosa create account-roles --classic --prefix ManagedOpenShift

# HCP
rosa create account-roles --hosted-cp --prefix ManagedOpenShift
```

### Using CLI-Created Roles with Terraform

For HCP, set `create_account_roles = false` to discover CLI-created roles:

```hcl
# HCP: discover roles created by rosa CLI
create_account_roles = false
account_role_prefix  = "ManagedOpenShift"  # Must match CLI --prefix
```

## Upgrade Procedures

### Classic Role Upgrades

Classic roles are updated on each `terraform apply` using the latest policies from the RHCS provider:

```bash
cd environments/commercial-classic
terraform apply  # Updates role policies to latest version
```

### HCP Account Role Upgrades

For multi-cluster HCP deployments, upgrade the account layer independently:

```bash
cd environments/account-hcp
terraform plan   # Review policy changes
terraform apply  # Update shared roles
```

Clusters automatically use the updated roles on next ROSA API interaction.

## Summary

| Scenario | Configuration |
|----------|---------------|
| Classic single cluster | Default (cluster_name prefix) |
| Classic multi-cluster | Each cluster uses its own cluster_name prefix |
| HCP single cluster | `create_account_roles = true` (default) |
| HCP multi-cluster | Account layer + `create_account_roles = false` |

## Related Documentation

- [OIDC Configuration](./OIDC.md) - OIDC setup for operator roles
- [ROADMAP](./ROADMAP.md) - Feature status and roadmap
