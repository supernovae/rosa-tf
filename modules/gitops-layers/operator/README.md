# GitOps Operator Module

This module installs the OpenShift GitOps operator (ArgoCD) on ROSA clusters and configures the GitOps Layers framework for Day 2 operations.

## Table of Contents

- [Overview](#overview)
- [Network Connectivity Requirements](#network-connectivity-requirements)
- [Authentication Requirements](#authentication-requirements)
- [Day 0 vs Day 2 Operations](#day-0-vs-day-2-operations)
- [Private Cluster Considerations](#private-cluster-considerations)
- [Installation Order](#installation-order)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Variables](#variables)
- [Outputs](#outputs)
- [Idempotency and Re-run Behavior](#idempotency-and-re-run-behavior)
- [Troubleshooting](#troubleshooting)

## Overview

This module provides:

1. **OpenShift GitOps Operator** - Installs ArgoCD for GitOps-based cluster management
2. **ConfigMap Bridge** - Stores cluster metadata and layer configuration for reference
3. **ArgoCD Instance** - Pre-configured ArgoCD with OpenShift OAuth integration
4. **Core Layers** - Terraform-managed operators with environment-specific configuration

## Architecture: Hybrid GitOps

This module uses a **hybrid approach** that combines Terraform and ArgoCD:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Terraform (Direct Method)                     │
├─────────────────────────────────────────────────────────────────┤
│  • Creates AWS infrastructure (S3 buckets, IAM roles)           │
│  • Installs operators (Loki, OADP, Virtualization, etc.)        │
│  • Deploys CRs with environment values (LokiStack, DPA)         │
│  • Creates ConfigMap bridge with cluster metadata               │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ArgoCD (Your Git Repo)                        │
├─────────────────────────────────────────────────────────────────┤
│  • Projects / Namespaces                                        │
│  • ResourceQuotas / LimitRanges                                 │
│  • NetworkPolicies                                              │
│  • RBAC (Roles, RoleBindings)                                   │
│  • Application deployments                                      │
│  • Any static manifests you want ArgoCD to manage               │
└─────────────────────────────────────────────────────────────────┘
```

### Why Hybrid?

**Core layers require Terraform** because they need environment-specific values:
- S3 bucket names (created by Terraform)
- IAM role ARNs (created by Terraform with OIDC trust)
- Retention periods, storage sizes, regions

These values cannot be known until Terraform creates the infrastructure.

**Your additional resources use ArgoCD** via `gitops_repo_url`:
- Static YAML manifests that don't need Terraform values
- GitOps-native with automatic sync
- Version controlled in your own repository

### ConfigMap Bridge

The `rosa-gitops-config` ConfigMap stores values for reference:

```yaml
data:
  cluster_name: "my-cluster"
  aws_region: "us-gov-west-1"
  monitoring_bucket_name: "my-cluster-123456-loki-logs"
  monitoring_role_arn: "arn:aws-us-gov:iam::123456:role/my-cluster-loki"
  # ... other values
```

Your ArgoCD applications can read these values if needed (e.g., for Kustomize replacements).

## Operator Channel Selection

This module automatically selects the correct operator channels based on OpenShift version. This ensures operators install correctly across different OCP releases.

### Channel Logic

| Operator | OCP 4.16-4.18 | OCP 4.19+ | Type |
|----------|---------------|-----------|------|
| Loki | `stable-6.2` | `stable-6.4` | Version-specific |
| Cluster Logging | `stable-6.2` | `stable-6.4` | Version-specific |
| OADP | `stable` | `stable` | Generic (auto-selects) |
| Virtualization | `stable` | `stable` | Generic (auto-selects) |
| Web Terminal | `fast` | `fast` | Generic (latest) |
| OpenShift GitOps | `latest` | `latest` | Generic (latest) |

### How It Works

1. The `openshift_version` variable is passed from the environment
2. The module parses the minor version (e.g., `4.20` → `20`)
3. Version-specific channels are selected from the `operator_channels` map
4. Subscriptions are rendered with the appropriate channel

### Adding New Version-Specific Operators

If a new operator requires version-specific channels:

1. Add the channel logic to `local.operator_channels` in `main.tf`:
   ```hcl
   operator_channels = {
     new_operator = local.ocp_minor_version >= 19 ? "stable-2.0" : "stable-1.5"
     # ... existing operators
   }
   ```

2. Create a template file (`subscription.yaml.tftpl`):
   ```yaml
   spec:
     channel: ${operator_channel}
   ```

3. Update the locals to use `templatefile()` with the channel

## Network Connectivity Requirements

**⚠️ CRITICAL: The Terraform runner must have network connectivity to the cluster API.**

This module requires direct HTTPS access to the cluster's API endpoint to:
1. Authenticate and obtain an OAuth token
2. Create Kubernetes resources (namespaces, subscriptions, configmaps)

### Connectivity Check

The `cluster-auth` module automatically validates connectivity:
- If the cluster API is **reachable**: Authentication proceeds, GitOps installs
- If the cluster API is **unreachable**: `authenticated = false`, GitOps is skipped

You will see this in Terraform output:
```
module.cluster_auth[0].auth_summary = {
  authenticated = false
  error         = "cluster not reachable"
  ...
}
```

### When Connectivity Fails

If GitOps installation is skipped due to connectivity issues:
1. The cluster will be created successfully
2. GitOps resources will NOT be installed
3. Re-run `terraform apply` after establishing connectivity

## Authentication Requirements

### Kubernetes Provider Authentication

This module uses the Terraform `kubernetes` provider to create resources on the cluster. The provider requires authentication via an OAuth bearer token.

**Authentication Flow:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Authentication Chain                          │
├─────────────────────────────────────────────────────────────────┤
│  1. Cluster created with htpasswd IDP (rhcs_identity_provider)  │
│  2. cluster-admin user created with password                     │
│  3. cluster-auth module exchanges credentials for OAuth token   │
│  4. kubernetes provider configured with token                   │
│  5. GitOps module creates resources on cluster                  │
└─────────────────────────────────────────────────────────────────┘
```

### Required Components

| Component | Purpose | Provider |
|-----------|---------|----------|
| htpasswd IDP | Identity provider for cluster-admin user | `rhcs_identity_provider` |
| cluster-admin user | User with cluster-admins group membership | `rhcs_group_membership` |
| cluster-auth module | OAuth token exchange | `modules/utility/cluster-auth` |
| kubernetes provider | Cluster resource management | `hashicorp/kubernetes` |

### System Requirements

- **curl**: Required for OAuth token exchange (available on most systems)
- **Network access**: Terraform must be able to reach the cluster API endpoint

## Day 0 vs Day 2 Operations

### Recommended: Day 0 Installation

**Day 0** means installing GitOps as part of the initial cluster provisioning.

```hcl
# In your tfvars or variables
install_gitops        = true
enable_layer_terminal = true
```

**Flow:**
1. Terraform creates the ROSA cluster
2. htpasswd IDP and cluster-admin user are created
3. cluster-auth module obtains OAuth token
4. GitOps operator is installed
5. All resources created in a single `terraform apply`

**Advantages:**
- Single operation - everything deployed together
- Guaranteed consistent state
- htpasswd IDP is always available

### Day 2 Installation (Caution Required)

**Day 2** means enabling GitOps on an existing cluster.

```hcl
# Enable GitOps on existing cluster
install_gitops = true  # Changed from false to true
```

**Flow:**
1. Terraform detects existing cluster
2. cluster-auth module obtains OAuth token using existing htpasswd credentials
3. GitOps operator is installed
4. Resources added to existing cluster

### ⚠️ Critical Warning: htpasswd IDP Dependency

**This module depends on the htpasswd identity provider being present on the cluster.**

If you:
- Remove the htpasswd IDP after cluster creation
- Replace htpasswd with another IDP (LDAP, OIDC, etc.)
- Delete the cluster-admin user

Then:
- **Day 2 GitOps installation will FAIL**
- The cluster-auth module cannot obtain an OAuth token
- Terraform cannot authenticate to the cluster

### Scenarios and Recommendations

| Scenario | htpasswd Present | Recommendation |
|----------|------------------|----------------|
| New cluster, want GitOps | N/A (will be created) | ✅ Use Day 0: `install_gitops = true` |
| Existing cluster with htpasswd | Yes | ✅ Day 2 works: enable `install_gitops = true` |
| Existing cluster, htpasswd removed | No | ❌ Day 2 will fail - reinstall htpasswd first |
| Want to remove htpasswd later | Currently present | ⚠️ Remove GitOps first, or use alternative auth |

### Best Practice

**For production clusters:**

1. Install GitOps at Day 0 with the cluster
2. If you must remove htpasswd IDP later:
   - Ensure GitOps is already installed
   - GitOps continues to work (uses service account)
   - But you cannot modify GitOps via Terraform without re-enabling htpasswd

## Private Cluster Considerations

### ⚠️ Two-Phase Deployment Required

**Private clusters (including ALL GovCloud clusters) require a two-phase deployment for GitOps.**

Even if you enable both `create_client_vpn = true` and `install_gitops = true`, GitOps will fail on the first apply because:

1. VPN infrastructure gets created, but...
2. You haven't connected to the VPN yet, so...
3. Terraform can't reach the cluster OAuth server to install GitOps

**You must actually connect to the VPN before GitOps can be installed.**

### Two-Phase Deployment Steps

```bash
# ═══════════════════════════════════════════════════════════════════
# PHASE 1: Deploy cluster and VPN (GitOps disabled)
# ═══════════════════════════════════════════════════════════════════

# In your tfvars:
#   install_gitops    = false    # Disabled for Phase 1
#   create_client_vpn = true     # Create VPN infrastructure

terraform apply -var-file=prod.tfvars
# Cluster: 45-60 min (Classic) or 15-20 min (HCP)
# VPN: 15-20 min

# ═══════════════════════════════════════════════════════════════════
# CONNECT TO VPN (required before Phase 2)
# ═══════════════════════════════════════════════════════════════════

# Download VPN configuration
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn

# Connect to VPN
sudo openvpn --config vpn-config.ovpn
# Or import into your VPN client (Tunnelblick, OpenVPN Connect, etc.)

# Verify connectivity (should succeed)
curl -sk https://$(terraform output -raw cluster_api_url)/healthz

# ═══════════════════════════════════════════════════════════════════
# PHASE 2: Install GitOps (while connected to VPN)
# ═══════════════════════════════════════════════════════════════════

# Update your tfvars:
#   install_gitops = true    # Now enabled

terraform apply -var-file=prod.tfvars
# GitOps installation: 2-5 min
```

### Why This Matters

| Scenario | Result |
|----------|--------|
| Phase 1 only (no VPN connection) | ✅ Cluster + VPN created, ❌ GitOps fails |
| Phase 1 + Phase 2 (connected to VPN) | ✅ Everything works |
| Single apply with GitOps enabled | ❌ Fails - can't reach OAuth server |

### Private Clusters

ROSA clusters deployed with `private_cluster = true` have API endpoints that are **only accessible from within the VPC**. This includes:

- **GovCloud clusters** (always private, FedRAMP requirement)
- **Commercial private clusters** (optional, but recommended for security)

> **Note**: Private ROSA clusters use AWS PrivateLink for Red Hat SRE access. Public clusters allow SRE access via the public API endpoint.

### Network Connectivity Options

For private clusters, the Terraform runner must have network access to the cluster VPC:

| Option | Description | When to Use |
|--------|-------------|-------------|
| **Client VPN** | Use the VPN module included in this project | Development, ad-hoc access |
| **Jump Host/Bastion** | Run Terraform from within VPC | CI/CD pipelines |
| **Transit Gateway** | Connect corporate network to VPC | Enterprise deployments |
| **Direct Connect** | AWS private connectivity | Production enterprise |

### Checking Connectivity Status

After `terraform apply`, check the cluster_auth output:

```bash
terraform output -json | jq '.cluster_auth_summary.value'
```

If `authenticated = false` and `error = "cluster not reachable"`:
1. Establish network connectivity to cluster VPC (connect to VPN)
2. Re-run `terraform apply`

## Installation Order

### Guaranteed Execution Order

GitOps installation is **always the final step** after all cluster infrastructure is ready:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Installation Order                            │
├─────────────────────────────────────────────────────────────────┤
│  1. VPC and Networking                                          │
│  2. KMS Keys (if enabled)                                       │
│  3. IAM Roles (account + operator roles)                        │
│  4. OIDC Provider                                               │
│  5. ROSA Cluster                                                │
│  6. Identity Provider (htpasswd)        ← Required for GitOps   │
│  7. Group Membership (cluster-admins)   ← Required for GitOps   │
│  8. Optional: VPN, Jump Host, OADP, Virtualization             │
│  9. Cluster Authentication (OAuth token) ← Validates cluster   │
│  10. GitOps Installation                 ← FINAL STEP           │
└─────────────────────────────────────────────────────────────────┘
```

### Enforced Dependencies

The GitOps module has explicit `depends_on` to ensure proper ordering:

```hcl
module "gitops" {
  # ...
  depends_on = [
    module.rosa_cluster,      # Cluster must exist
    module.cluster_auth,      # Authentication must succeed
    module.oadp_resources,    # Optional dependencies ready
    module.virtualization_resources
  ]
}
```

### Conditional Installation

GitOps only installs when ALL conditions are met:

1. `install_gitops = true`
2. Cluster exists and is ready
3. htpasswd IDP is configured
4. Cluster API is reachable
5. OAuth authentication succeeds

If any condition fails, GitOps is skipped gracefully and can be installed on subsequent runs.

## Prerequisites

### 1. Cluster with htpasswd IDP

The ROSA cluster must have:

```hcl
# In cluster module
resource "rhcs_identity_provider" "htpasswd" {
  cluster = rhcs_cluster_rosa_classic.this.id
  name    = "htpasswd"
  htpasswd = {
    users = [{
      username = "cluster-admin"
      password = random_password.admin.result
    }]
  }
}

resource "rhcs_group_membership" "cluster_admin" {
  cluster = rhcs_cluster_rosa_classic.this.id
  group   = "cluster-admins"
  user    = "cluster-admin"
}
```

### 2. cluster-auth Module

Configure authentication in your environment:

```hcl
module "cluster_auth" {
  source = "../../modules/utility/cluster-auth"
  count  = var.install_gitops ? 1 : 0

  enabled  = var.install_gitops
  api_url  = module.rosa_cluster.api_url
  username = module.rosa_cluster.admin_username
  password = module.rosa_cluster.admin_password
}
```

### 3. Kubernetes Provider Configuration

Configure the provider with the obtained token:

```hcl
provider "kubernetes" {
  host  = var.install_gitops ? module.cluster_auth[0].host : ""
  token = var.install_gitops ? module.cluster_auth[0].token : ""

  # Skip TLS verification for self-signed certificates
  # For production, configure proper CA certificate
  insecure = true
}
```

## Usage

### Basic Usage

```hcl
module "gitops" {
  source = "../../modules/gitops-layers/operator"
  count  = var.install_gitops ? 1 : 0

  depends_on = [
    module.rosa_cluster,
    module.cluster_auth
  ]

  cluster_name    = var.cluster_name
  cluster_api_url = module.rosa_cluster.api_url
  aws_region      = var.aws_region
  aws_account_id  = data.aws_caller_identity.current.account_id

  # Enable desired layers
  enable_layer_terminal       = true
  enable_layer_oadp           = false
  enable_layer_virtualization = false
}
```

### With OADP Backup Layer

```hcl
module "gitops" {
  source = "../../modules/gitops-layers/operator"
  count  = var.install_gitops ? 1 : 0

  # ... base configuration ...

  enable_layer_oadp = true
  oadp_bucket_name  = module.oadp_resources[0].bucket_name
  oadp_role_arn     = module.oadp_resources[0].role_arn
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `cluster_name` | string | Name of the ROSA cluster |
| `cluster_api_url` | string | API URL of the cluster |
| `cluster_token` | string | OAuth bearer token (from cluster-auth module) |
| `aws_region` | string | AWS region |
| `aws_account_id` | string | AWS account ID |

### Cluster Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_type` | string | `"hcp"` | Cluster type: `"classic"` or `"hcp"`. Affects monitoring (Classic skips PrometheusRules in SRE-managed namespace) |
| `openshift_version` | string | `"4.20"` | OpenShift version for operator channel selection |

### Layer Enablement

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_layer_terminal` | bool | `true` | Enable Web Terminal operator |
| `enable_layer_oadp` | bool | `false` | Enable OADP backup layer (requires OADP config) |
| `enable_layer_virtualization` | bool | `false` | Enable OpenShift Virtualization (requires bare metal) |
| `enable_layer_monitoring` | bool | `false` | Enable Prometheus + Loki monitoring stack |

### OADP Configuration (when `enable_layer_oadp = true`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `oadp_bucket_name` | string | `""` | S3 bucket name for backups |
| `oadp_role_arn` | string | `""` | IAM role ARN for OADP |
| `oadp_backup_retention_days` | number | `7` | Days to retain nightly backups (0 disables schedule) |

### Monitoring Configuration (when `enable_layer_monitoring = true`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `monitoring_bucket_name` | string | `""` | S3 bucket name for Loki logs |
| `monitoring_role_arn` | string | `""` | IAM role ARN for Loki S3 access |
| `monitoring_loki_size` | string | `"1x.extra-small"` | LokiStack size: `1x.demo`, `1x.extra-small`, `1x.small`, `1x.medium` |
| `monitoring_retention_days` | number | `30` | Days to retain logs and metrics |
| `monitoring_storage_class` | string | `"gp3-csi"` | StorageClass for PVCs |
| `monitoring_prometheus_storage_size` | string | `"100Gi"` | Prometheus PVC size |

### Virtualization Configuration (when `enable_layer_virtualization = true`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `virt_node_selector` | map(string) | `{ "node-role.kubernetes.io/virtualization" = "" }` | Node selector for HyperConverged CR |
| `virt_tolerations` | list(object) | `[{ key = "virtualization", ... }]` | Tolerations for HyperConverged CR |

### Installation Method

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `layers_install_method` | string | `"direct"` | `"direct"` (recommended) or `"applicationset"` |
| `gitops_repo_url` | string | (default repo) | Git repo URL for YOUR additional static resources |
| `gitops_repo_revision` | string | `"main"` | Git branch/tag/commit |
| `gitops_repo_path` | string | `"layers"` | Path within repo to manifests |

**Note:** Core layers (monitoring, OADP, virtualization) are always installed via Terraform's direct method because they require environment-specific values. The `gitops_repo_url` is for your **additional** static resources that ArgoCD will sync.

### Advanced

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `additional_config_data` | map(string) | `{}` | Additional ConfigMap key-value pairs |

## Outputs

| Output | Description |
|--------|-------------|
| `namespace` | Namespace where GitOps is installed (`openshift-gitops`) |
| `configmap_name` | Name of the ConfigMap bridge (`rosa-gitops-config`) |
| `configmap_namespace` | Namespace of the ConfigMap bridge |
| `argocd_url` | Command to get ArgoCD console URL |
| `argocd_admin_password` | Command to get ArgoCD admin password |
| `layers_enabled` | Map of enabled layers (terminal, oadp, virtualization, monitoring) |
| `layers_repo` | GitOps layers repository configuration |
| `applicationset_deployed` | Whether ApplicationSet was deployed |
| `install_instructions` | Instructions for accessing GitOps |

## Idempotency and Re-run Behavior

This module is designed to be **safe to re-run**. Running `terraform apply` multiple times will not reinstall operators or recreate resources unnecessarily.

### How It Works

Resources use **stable triggers** based on content, not execution order:

| Resource Type | Trigger | Re-runs when... |
|--------------|---------|-----------------|
| Connectivity check | Every apply | Always (quick validation) |
| Core GitOps (namespace, subscription, rbac, argocd) | Cluster URL | Never after initial creation |
| ConfigMap bridge | Content hash | Layer toggles or metadata changes |
| Layer operators (Terminal, OADP, Virtualization) | YAML hash | Layer YAML content changes |
| CRD readiness checks | Cluster URL | Never after initial creation |

### Expected Behavior

**First apply (new cluster):**
```
null_resource.validate_connection: Creating...
null_resource.create_namespace: Creating...
null_resource.create_subscription: Creating...
time_sleep.wait_for_operator: Creating...
... (all resources created)
```

**Subsequent applies (no changes):**
```
null_resource.validate_connection: Creating...    # Always runs - connectivity check
null_resource.validate_connection: Creation complete after 1s

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

**When you change a layer toggle:**
```
null_resource.validate_connection: Creating...
null_resource.create_configmap: Destroying... [id=...]
null_resource.create_configmap: Creating...      # ConfigMap content changed
```

### Why This Matters

- **Fast re-runs**: Only connectivity validation runs on each apply (~1-2 seconds)
- **Safe operations**: Accidentally running `terraform apply` won't disrupt existing operators
- **Predictable changes**: Resources only update when their actual content changes
- **Proper ordering**: `depends_on` ensures correct sequencing even with stable triggers

### Script Idempotency

The underlying installation script handles already-existing resources gracefully:

```
>>> Creating Namespace
HTTP Status: 409
OK (already exists)
```

HTTP 409 (Conflict) is treated as success - the resource already exists, which is the desired state.

## Troubleshooting

### Authentication Errors

**Error:** `Failed to construct REST client: no client config`

**Cause:** Kubernetes provider cannot authenticate to the cluster.

**Solutions:**
1. Verify htpasswd IDP exists on the cluster
2. Check cluster-auth module outputs for errors
3. Ensure cluster is accessible from Terraform host
4. Verify `install_gitops = true` is set

### Token Retrieval Failures

**Error:** `authentication failed` in cluster-auth module

**Cause:** OAuth token exchange failed.

**Solutions:**
1. Verify cluster-admin user exists
2. Check password is correct (from Terraform state)
3. Test manually: `curl -u cluster-admin:<password> <api-url>/oauth/authorize`
4. Ensure cluster API is reachable

### OAuth Retry Behavior

The cluster-auth module includes automatic retry logic to handle temporary OAuth unavailability. This is common during initial cluster creation when the OAuth server restarts after IDP configuration.

**Default behavior:**
- 6 retry attempts with exponential backoff (10s → 20s → 30s...)
- ~2 minute maximum wait before failing
- Permanent errors (invalid credentials, access forbidden) fail immediately

**Customization via environment variables:**

```bash
export OAUTH_MAX_RETRIES=10      # Default: 6
export OAUTH_INITIAL_WAIT=5      # Default: 10 seconds  
export OAUTH_MAX_WAIT=60         # Default: 30 seconds
```

**When you see retry messages:**
```
OAuth token retrieval attempt 1 failed (oauth_not_reachable), retrying in 10s...
```

This is normal during cluster creation - the OAuth server is restarting after htpasswd IDP was added. The retry logic handles this automatically.

### htpasswd IDP Missing

**Error:** Cannot authenticate after removing htpasswd IDP

**Solutions:**
1. Re-create htpasswd IDP with same credentials
2. Or set `install_gitops = false` and manage GitOps manually
3. For future: Install GitOps at Day 0 before removing htpasswd

### Operator Installation Timeout

**Error:** Timeout waiting for GitOps operator

**Cause:** Operator installation taking longer than expected.

**Solutions:**
1. Check cluster has sufficient resources
2. Verify OperatorHub is accessible (not air-gapped without mirror)
3. Check: `oc get csv -n openshift-operators | grep gitops`

## Destroying Clusters

### Skip GitOps on Destroy

When destroying a cluster, the GitOps module requires OAuth authentication to the cluster API. This can fail if:

- The cluster is already being deleted
- VPN connectivity is not available (private clusters)
- Network path to cluster doesn't exist from Terraform runner

**Solution:** Disable GitOps and all layers during destroy:

```bash
terraform destroy \
  -var-file="dev.tfvars" \
  -var="install_gitops=false" \
  -var="enable_layer_monitoring=false" \
  -var="enable_layer_oadp=false" \
  -var="enable_layer_terminal=false" \
  -var="enable_layer_virtualization=false"
```

**Why this works:**
- GitOps resources (operators, ArgoCD, LokiStack) live inside the cluster
- They are automatically destroyed when the cluster is deleted
- Disabling the module skips the authentication that would fail
- All AWS resources (VPC, IAM, etc.) are still properly cleaned up

### Private/PrivateLink Clusters

For private clusters where the Terraform runner has no network access:

1. **Don't connect to VPN** - You may need to destroy the VPN itself
2. **Run destroy with GitOps disabled** - As shown above
3. **VPN and cluster will be destroyed** - No cluster connectivity needed

This is especially important when destroying the VPN that provides cluster access (chicken-and-egg problem).

### S3 Buckets

S3 buckets for Loki logs and OADP backups are **not** automatically deleted. See [OPERATIONS.md](../../../docs/OPERATIONS.md#s3-bucket-cleanup-manual-step) for manual cleanup steps.
