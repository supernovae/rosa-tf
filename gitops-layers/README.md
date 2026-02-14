# GitOps Layers for ROSA

GitOps integration for ROSA clusters using native Terraform providers and ArgoCD.

> **Repo**: [supernovae/rosa-tf](https://github.com/supernovae/rosa-tf)

## Architecture: Hybrid GitOps

This framework uses a **hybrid approach** that combines Terraform and ArgoCD:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Terraform (Direct Method)                    │
├─────────────────────────────────────────────────────────────────┤
│  • Creates AWS infrastructure (S3 buckets, IAM roles)           │
│  • Installs operators (Loki, OADP, Virtualization, etc.)        │
│  • Deploys CRs with environment values (LokiStack, DPA)         │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│              ArgoCD (Your Git Repo - Optional)                  │
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
| **Add your own resources** | Above + `gitops_repo_url = "https://github.com/your-org/your-manifests.git"` |
| **GitOps only, no layers** | `install_gitops = true` + all `enable_layer_* = false` |

```hcl
# Enable layers (Terraform applies them directly)
install_gitops          = true
enable_layer_monitoring = true
enable_layer_oadp       = true

# Optional: Add YOUR static resources via ArgoCD Application
# gitops_repo_url = "https://github.com/your-org/your-manifests.git"
```

## Local Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| `terraform` | Yes | Infrastructure and cluster resource management |
| `jq` | Recommended | Parses JSON output from Terraform |

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
| `certmanager` | Cert-Manager with Let's Encrypt DNS01 + custom ingress | Route53 zone, IAM role, NLB |

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

# Enable Virtualization (requires bare metal machine pool)
enable_layer_virtualization = true
# See examples/ocpvirtualization.tfvars for machine pool config
```

### Additional GitOps Configuration

To deploy your own custom resources (projects, quotas, RBAC, apps) alongside the
built-in layers, provide a `gitops_repo_url`. An ArgoCD Application will be
created automatically to sync from your repo:

```hcl
# terraform.tfvars
install_gitops       = true
gitops_repo_url      = "https://github.com/your-org/my-cluster-config.git"
gitops_repo_path     = "."        # path within repo (default: gitops-layers/layers)
gitops_repo_revision = "main"     # branch, tag, or commit
```

> **Note:** This does NOT replace the built-in layers. Core layers (monitoring,
> OADP, virtualization) are always managed by Terraform because they depend on
> infrastructure it creates (S3 buckets, IAM roles, etc.).

## Minimal GitOps (No Layers)

With all `enable_layer_*` set to false, Terraform still installs ArgoCD. You can use this as a foundation for your own GitOps resources via the external repo.

```hcl
# GitOps with ArgoCD only (no operator layers)
install_gitops        = true
enable_layer_terminal = false
enable_layer_oadp     = false
```

## External Repo Application (Custom Resources)

When you provide a `gitops_repo_url`, a single ArgoCD Application is created to sync
your custom Kubernetes manifests. This is independent of the built-in layers.

> **Note:** Core layers (monitoring, OADP, virtualization) are always applied by
> Terraform regardless, because they require environment-specific values.

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
install_gitops       = true
gitops_repo_url      = "https://github.com/your-org/your-gitops-repo.git"
gitops_repo_path     = "."     # or subdirectory
gitops_repo_revision = "main"
```

ArgoCD will sync your manifests automatically when changes are pushed to Git.

📖 **[OAuth Troubleshooting](../docs/OPERATIONS.md#gitops-troubleshooting)** - Debug authentication issues

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
   - Create `layer-<name>.tf` in `modules/gitops-layers/operator/`
   - Create Terraform module for AWS resources (if needed)
   - Wire through all 4 environments (see `.cursor/rules/gitops-variables.mdc`)

## Layer Dependencies

Some layers require Terraform-managed AWS resources:

### OADP Layer
- **S3 Bucket**: For backup storage
- **IAM Role**: With OIDC trust for the OADP operator service account

### Virtualization Layer
- **Bare Metal Machine Pool**: Required for KubeVirt nested virtualization

### Cert-Manager Layer
- **Route53 Hosted Zone**: For DNS01 ACME challenges (existing or Terraform-created)
- **IAM Role**: With OIDC trust for the cert-manager service account
- **NLB**: Custom IngressController with its own Network Load Balancer
- **Route53 CNAME**: Wildcard record pointing to the custom NLB

See [modules/gitops-layers/certmanager/README.md](../modules/gitops-layers/certmanager/README.md) for full documentation.

## Best Practices

1. **Use Kustomize**: Structure configurations for easy customization
2. **Sync Waves**: Use ArgoCD sync waves for dependency ordering
3. **Health Checks**: Define health checks for CRs
4. **Secrets Management**: Use External Secrets or Sealed Secrets for sensitive data
5. **Testing**: Test layers in a non-production cluster first

## Troubleshooting

### Layer not deploying

1. Check that the layer is enabled in your tfvars:
   ```bash
   grep enable_layer_ *.tfvars
   ```

2. Re-run Terraform to reconcile:
   ```bash
   terraform apply -var-file=prod.tfvars
   ```

3. Check Terraform state for the layer resources:
   ```bash
   terraform state list | grep layer_<name>
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
