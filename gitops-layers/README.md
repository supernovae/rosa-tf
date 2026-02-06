# GitOps Layers for ROSA

GitOps integration for ROSA clusters using ArgoCD and the ConfigMap bridge pattern.

> **Repo**: [supernovae/rosa-tf](https://github.com/supernovae/rosa-tf)

## Architecture: Hybrid GitOps

This framework uses a **hybrid approach** that combines Terraform and ArgoCD:

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
│              ArgoCD (Your Git Repo - Optional)                   │
├─────────────────────────────────────────────────────────────────┤
│  • Projects / Namespaces                                        │
│  • ResourceQuotas / LimitRanges                                 │
│  • NetworkPolicies                                              │
│  • RBAC (Roles, RoleBindings)                                   │
│  • Application deployments                                      │
│  • Any static manifests you want ArgoCD to manage               │
└─────────────────────────────────────────────────────────────────┘
```

**Why Hybrid?**

Core layers (monitoring, OADP, etc.) are **always managed by Terraform** because they require:
- S3 bucket names (created by Terraform)
- IAM role ARNs (created by Terraform with OIDC trust)
- Region, retention periods, storage sizes

These values cannot be known until Terraform creates the infrastructure.

The `gitops_repo_url` is for **your additional static resources** that ArgoCD syncs from your Git repo.

## Quick Start

| What You Want | Configuration |
|---------------|---------------|
| **Enable layers (default)** | `install_gitops = true` + enable desired `enable_layer_*` flags |
| **Add your own resources** | Above + `layers_install_method = "applicationset"` + `gitops_repo_url = "..."` |
| **GitOps only, no layers** | `install_gitops = true` + all `enable_layer_* = false` |

```hcl
# Enable layers (Terraform applies them directly)
install_gitops          = true
enable_layer_monitoring = true
enable_layer_oadp       = true

# Optional: Add YOUR static resources via ArgoCD
layers_install_method = "applicationset"
gitops_repo_url       = "https://github.com/your-org/your-manifests.git"
```

## Local Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| `curl` | Yes | HTTP requests to cluster API for OAuth token retrieval |
| `jq` | Recommended | Parses JSON responses from OAuth/API endpoints |

**Install jq:**
```bash
# macOS
brew install jq

# RHEL/Fedora
dnf install jq

# Ubuntu/Debian
apt-get install jq
```

## Available Layers

| Layer | Description | Terraform Dependencies |
|-------|-------------|----------------------|
| `terminal` | OpenShift Web Terminal operator | None |
| `monitoring` | Prometheus + Loki logging stack | S3 bucket, IAM role |
| `oadp` | OpenShift API for Data Protection (backup/restore) | S3 bucket, IAM role |
| `virtualization` | OpenShift Virtualization (KubeVirt) | Bare metal machine pool |

## Layer Structure

Each layer follows this structure:

```
layers/
└── <layer-name>/
    ├── kustomization.yaml    # Kustomize configuration
    ├── namespace.yaml        # Required namespaces (optional)
    ├── subscription.yaml     # Operator subscription
    └── <config>.yaml         # Operator configuration CRs
```

## Using Layers

### Enable via Terraform

```hcl
# terraform.tfvars

# Enable GitOps with default layers
install_gitops = true
enable_layer_terminal = true  # Default: true

# Enable OADP (requires additional Terraform resources)
enable_layer_oadp = true

# Enable Virtualization (requires bare metal nodes)
enable_layer_virtualization = true
virt_node_count = 3
virt_machine_type = "m5.metal"
```

### Custom Layers Repository

To use your own customized layers instead of the reference implementations:

```hcl
# terraform.tfvars
install_gitops     = true
gitops_repo_url      = "https://github.com/your-org/your-rosa-layers.git"
gitops_repo_path     = "gitops-layers/layers"
gitops_repo_revision = "main"
```

## Customizing Without Layers

Even with all `enable_layer_*` set to false, the **base layer** is always applied when
`install_gitops = true`. Use `layers/base/` to customize:

- Cluster-wide defaults (resource quotas, limit ranges)
- Project templates and configurations
- RBAC policies and cluster roles
- Any cluster configurations you want GitOps-managed

```hcl
# GitOps with only base customizations (no operator layers)
install_gitops        = true
enable_layer_terminal = false
enable_layer_oadp     = false
```

## Using ApplicationSet Method (For Your Additional Resources)

The ApplicationSet method deploys **your own static resources** via ArgoCD - things like projects, quotas, RBAC, and application deployments.

> **Note:** Core layers (monitoring, OADP, virtualization) are always applied by Terraform regardless of this setting, because they require environment-specific values.

### Setup Your GitOps Repository

Create a repository with your Kubernetes manifests:

```
your-gitops-repo/
├── namespaces/
│   ├── team-a.yaml
│   └── team-b.yaml
├── quotas/
│   └── default-quota.yaml
├── rbac/
│   └── developer-role.yaml
└── kustomization.yaml
```

### Configure Terraform

```hcl
install_gitops         = true
layers_install_method  = "applicationset"
gitops_repo_url        = "https://github.com/your-org/your-gitops-repo.git"
gitops_repo_path       = "."  # or subdirectory
gitops_repo_revision   = "main"
```

ArgoCD will sync your manifests automatically when changes are pushed to Git.

📖 **[OAuth Troubleshooting](../docs/OPERATIONS.md#gitops-troubleshooting)** - Debug authentication issues

## ConfigMap Bridge

Terraform creates a ConfigMap `rosa-gitops-config` in `openshift-gitops` namespace containing:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rosa-gitops-config
  namespace: openshift-gitops
data:
  cluster_name: "my-cluster"
  aws_region: "us-east-1"
  
  # Layer flags
  layer_terminal_enabled: "true"
  layer_oadp_enabled: "true"
  layer_virtualization_enabled: "false"
  
  # OADP configuration (when enabled)
  oadp_bucket_name: "my-cluster-oadp-backups"
  oadp_bucket_region: "us-east-1"
  oadp_role_arn: "arn:aws:iam::123456789012:role/my-cluster-oadp"
```

This bridge pattern allows GitOps-deployed operators to inherit Terraform-managed values
(S3 buckets, KMS keys, IAM roles) without storing sensitive data in Git.

## Adding New Layers

1. Create a new directory under `layers/`:
   ```
   mkdir -p layers/my-layer
   ```

2. Create the required files:
   - `kustomization.yaml` - Kustomize configuration
   - `subscription.yaml` - Operator subscription (if applicable)
   - Additional configuration CRs

3. Update Terraform variables (if layer needs AWS resources):
   - Add `enable_layer_<name>` variable
   - Create Terraform module for AWS resources
   - Add layer to ApplicationSet generator

4. Update the ConfigMap bridge with new layer flag

## Layer Dependencies

Some layers require Terraform-managed AWS resources:

### OADP Layer
- **S3 Bucket**: For backup storage
- **IAM Role**: With OIDC trust for the OADP operator service account

### Virtualization Layer
- **Bare Metal Machine Pool**: Required for KubeVirt nested virtualization

## Best Practices

1. **Use Kustomize**: Structure configurations for easy customization
2. **Sync Waves**: Use ArgoCD sync waves for dependency ordering
3. **Health Checks**: Define health checks for CRs
4. **Secrets Management**: Use External Secrets or Sealed Secrets for sensitive data
5. **Testing**: Test layers in a non-production cluster first

## Troubleshooting

### Layer not deploying

1. Check ApplicationSet status:
   ```bash
   oc get applicationset rosa-layers -n openshift-gitops -o yaml
   ```

2. Check Application status:
   ```bash
   oc get applications -n openshift-gitops
   ```

3. Verify ConfigMap bridge:
   ```bash
   oc get configmap rosa-gitops-config -n openshift-gitops -o yaml
   ```

### Operator installation stuck

1. Check subscription status:
   ```bash
   oc get subscription -n openshift-operators
   oc get csv -n openshift-operators
   ```

2. Check for install plan approval:
   ```bash
   oc get installplan -n openshift-operators
   ```
