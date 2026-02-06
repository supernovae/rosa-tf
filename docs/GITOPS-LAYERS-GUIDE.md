# GitOps Layers Developer Guide

This guide explains how to add new GitOps layers to the ROSA Terraform framework.

## Important: Hybrid Architecture

**Core layers are always managed by Terraform**, not pulled from Git by ArgoCD. This is because layers like monitoring and OADP require environment-specific values (S3 bucket names, IAM role ARNs) that Terraform creates.

| What | Managed By | Why |
|------|------------|-----|
| S3 buckets, IAM roles | Terraform | Creates the AWS infrastructure |
| Operators + CRs with env values | Terraform (direct) | Needs bucket/role ARNs |
| Your additional static resources | ArgoCD (optional) | Projects, quotas, RBAC, apps |

The `gitops_repo_url` variable is for **your own additional static resources**, not for the core layers.

## Architecture Overview

GitOps layers are modular components that add Day 2 capabilities to ROSA clusters:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Environment (main.tf)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────┐           │
│  │  gitops_resources    │    │  gitops (operator)   │           │
│  │  (AWS infrastructure)│───▶│  (K8s manifests)     │           │
│  └──────────────────────┘    └──────────────────────┘           │
│            │                           │                        │
│            ▼                           ▼                        │
│  ┌──────────────────────┐    ┌──────────────────────┐           │
│  │ - S3 buckets         │    │ - Operators          │           │
│  │ - IAM roles          │    │ - CRDs               │           │
│  │ - Machine pools      │    │ - ConfigMaps         │           │
│  └──────────────────────┘    └──────────────────────┘           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key Principle:** Separation of concerns
- **gitops-layers/resources**: AWS infrastructure (S3, IAM, machine pools)
- **gitops-layers/operator**: Kubernetes resources (operators, CRs, configs)

## Directory Structure

```
modules/gitops-layers/
├── shared/
│   └── layer-variables.tf     # Shared variable definitions
├── resources/
│   ├── main.tf                # Consolidates all layer infrastructure
│   ├── variables.tf           # Input variables
│   └── outputs.tf             # Outputs for operator module
├── operator/
│   ├── main.tf                # Installs operators and applies manifests
│   └── install-gitops.sh      # Shell script for API calls
├── oadp/                      # OADP infrastructure (S3 + IAM)
├── monitoring/                # Monitoring infrastructure (S3 + IAM for Loki)
├── virtualization/            # Virtualization infrastructure (machine pool)
└── [new-layer]/               # Add new layer modules here
```

## Adding a New Layer

### Step 1: Define Variables

Add variables to `modules/gitops-layers/shared/layer-variables.tf`:

```hcl
# In shared/layer-variables.tf

variable "enable_layer_newlayer" {
  type        = bool
  description = "Enable NewLayer (description of what it does)."
  default     = false
}

variable "newlayer_some_config" {
  type        = string
  description = "Configuration for NewLayer."
  default     = "default-value"
}
```

Then copy these variables to each environment's `variables.tf`:
- `environments/commercial-classic/variables.tf`
- `environments/commercial-hcp/variables.tf`
- `environments/govcloud-classic/variables.tf`
- `environments/govcloud-hcp/variables.tf`

### Step 2: Create Infrastructure Module (if needed)

If your layer needs AWS resources (S3, IAM, etc.), create a module:

```bash
mkdir modules/gitops-layers/newlayer
```

**modules/gitops-layers/newlayer/main.tf:**
```hcl
# Data sources for account info
data "aws_caller_identity" "current" {}

# S3 bucket naming - must be DNS compliant (3-63 chars)
# Pattern: {cluster_name}-{account_id}-{suffix}
# Account ID = 12 chars, so max cluster_name = 63 - 12 - suffix_len - 2
locals {
  bucket_suffix       = "newlayer-data"  # Your suffix here
  bucket_max_name_len = 63 - 12 - length(local.bucket_suffix) - 2
  bucket_cluster_name = substr(lower(replace(var.cluster_name, "_", "-")), 0, local.bucket_max_name_len)
  bucket_name         = "${local.bucket_cluster_name}-${data.aws_caller_identity.current.account_id}-${local.bucket_suffix}"
}

# Create required AWS resources
resource "aws_s3_bucket" "newlayer" {
  bucket = local.bucket_name
  # ...
}

resource "aws_iam_role" "newlayer" {
  name = "${var.cluster_name}-newlayer-role"
  # ...
}
```

> **Important**: S3 bucket names are globally unique across ALL AWS accounts. Always include the account ID and ensure the total name is ≤ 63 characters.

**modules/gitops-layers/newlayer/outputs.tf:**
```hcl
output "bucket_name" {
  value = aws_s3_bucket.newlayer.id
}

output "role_arn" {
  value = aws_iam_role.newlayer.arn
}
```

### Step 3: Register in Resources Module

Add your module to `modules/gitops-layers/resources/main.tf`:

```hcl
# In resources/main.tf

module "newlayer" {
  source = "../newlayer"
  count  = var.enable_layer_newlayer ? 1 : 0

  cluster_name      = var.cluster_name
  oidc_endpoint_url = var.oidc_endpoint_url
  # ... other required inputs
}
```

Add outputs to `modules/gitops-layers/resources/outputs.tf`:

```hcl
output "newlayer_bucket_name" {
  value = var.enable_layer_newlayer ? module.newlayer[0].bucket_name : ""
}

output "newlayer_role_arn" {
  value = var.enable_layer_newlayer ? module.newlayer[0].role_arn : ""
}
```

### Step 4: Add Kubernetes Manifests

Create manifests in `gitops-layers/layers/newlayer/`:

```
gitops-layers/layers/newlayer/
├── kustomization.yaml
├── namespace.yaml
├── subscription.yaml.tftpl    # Operator subscription (templated)
├── operatorgroup.yaml
└── custom-resource.yaml.tftpl # Layer CR (templated)
```

### Step 5: Add Operator Module Logic

Update `modules/gitops-layers/operator/main.tf` to deploy your layer:

```hcl
# Add locals for templates
locals {
  newlayer_subscription = templatefile("${local.layers_path}/newlayer/subscription.yaml.tftpl", {
    # template variables
  })
}

# Add namespace resource
resource "null_resource" "layer_newlayer_namespace_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_newlayer ? 1 : 0
  # ...
}

# Add subscription resource
resource "null_resource" "layer_newlayer_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_newlayer ? 1 : 0
  # ...
  depends_on = [null_resource.layer_newlayer_namespace_direct]
}

# Add custom resource (after CRD is ready)
resource "null_resource" "layer_newlayer_cr_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_newlayer ? 1 : 0
  # ...
  depends_on = [null_resource.wait_for_newlayer_crd]
}
```

### Step 6: Update Operator Variables

Add variables to `modules/gitops-layers/operator/variables.tf`:

```hcl
variable "enable_layer_newlayer" {
  type        = bool
  description = "Enable NewLayer."
  default     = false
}

variable "newlayer_bucket_name" {
  type        = string
  description = "S3 bucket for NewLayer."
  default     = ""
}

variable "newlayer_role_arn" {
  type        = string
  description = "IAM role for NewLayer."
  default     = ""
}
```

### Step 7: Wire Up Environments

The environments already use the consolidated `gitops_resources` module, so you just need to:

1. Add the enable flag passthrough in resources module variables
2. Add any layer-specific config variables
3. Add output passthrough in resources module
4. Pass outputs to the operator module

Since environments use:
```hcl
module "gitops_resources" {
  # ... automatically picks up new layers
}

module "gitops" {
  # ... wire outputs
  newlayer_bucket_name = length(module.gitops_resources) > 0 ? module.gitops_resources[0].newlayer_bucket_name : ""
}
```

## Layer Types

### Type 1: Operator-Only (No AWS Infrastructure)

Example: **Web Terminal**

- Just needs operator subscription
- No S3, IAM, or other AWS resources
- Add to operator module only

### Type 2: Operator + AWS Infrastructure

Example: **OADP**

- Needs S3 bucket for backups
- Needs IAM role for Velero
- Requires infrastructure module + operator logic

Example: **Monitoring** (Prometheus + Loki)

- Needs S3 bucket for Loki log storage
- Needs IAM role for Loki S3 access (STS/IRSA)
- Installs multiple operators (Loki, Cluster Logging, Cluster Observability)
- Creates LokiStack, ClusterLogForwarder, UIPlugin
- **Note:** PrometheusRules are only deployed on HCP clusters (Classic has SRE-managed namespace)

### Type 3: Infrastructure-Only

Example: **Virtualization**

- Needs bare metal machine pool
- No operator (uses built-in OCP Virtualization)
- Infrastructure module only

## Testing a New Layer

1. **Validate Terraform:**
   ```bash
   cd environments/commercial-classic
   terraform init
   terraform validate
   ```

2. **Test with a dev cluster:**
   ```bash
   # Enable your layer
   terraform apply -var="enable_layer_newlayer=true" -var-file=dev.tfvars
   ```

3. **Verify in cluster:**
   ```bash
   oc get subscription -n openshift-newlayer
   oc get <custom-resource> -n openshift-newlayer
   ```

## Best Practices

1. **Fail gracefully**: Use `count` to conditionally create resources
2. **Template everything**: Use `.tftpl` files for Kubernetes manifests
3. **Wait for CRDs**: Add `wait_for_*_crd` resources before applying CRs
4. **Document**: Add README.md to each layer module
5. **Test all 4 environments**: Classic/HCP differences can cause issues

## Classic vs HCP Considerations

| Aspect | Classic | HCP |
|--------|---------|-----|
| Machine pools | `rhcs_machine_pool` | `rhcs_hcp_machine_pool` |
| OAuth | `oauth-openshift.apps.*` | `oauth.*` |
| Bare metal | Available | Limited availability |
| openshift-monitoring | SRE-managed (read-only) | User-managed (full access) |
| PrometheusRules | ❌ Blocked by admission webhook | ✅ Fully supported |

Handle differences in the operator module with:
```hcl
# Skip PrometheusRules on Classic (SRE owns openshift-monitoring namespace)
count = var.enable_layer_monitoring && var.cluster_type == "hcp" ? 1 : 0
```

Handle differences in the resources module with:
```hcl
count = var.enable_layer_x && var.cluster_type == "classic" ? 1 : 0
```

## Troubleshooting

**Layer not deploying:**
- Check `install_gitops = true` in tfvars
- Verify OAuth token obtained: `terraform output cluster_auth_summary`
- Check operator module logs in Terraform output

**CRD not ready:**
- Increase wait time in `wait_for_*_crd` resource
- Check operator pod logs: `oc logs -n openshift-operators`

**AWS permissions:**
- Verify IAM role trust policy includes OIDC
- Check service account annotation matches role ARN
