# FedRAMP Deployment Guide

This guide covers how to deploy and operate this ROSA Terraform framework in a FedRAMP-controlled environment. It is intended for organizations operating under **FedRAMP High**, **DoD IL4/IL5**, **NIST 800-53**, or similar regulatory controls.

## Table of Contents

- [Overview](#overview)
- [Fork and Control the Repository](#fork-and-control-the-repository)
- [Disable Terraform Telemetry](#disable-terraform-telemetry)
- [Security Scanning](#security-scanning)
- [Vendor Terraform Providers](#vendor-terraform-providers)
- [Terraform Identity and Security Controls](#terraform-identity-and-security-controls)
- [FedRAMP Configuration Checklist](#fedramp-configuration-checklist)
- [Related Documentation](#related-documentation)

---

## Overview

The GovCloud environments (`govcloud-classic`, `govcloud-hcp`) are already configured with FedRAMP-appropriate defaults:

- **FIPS mode** enabled (mandatory, cannot be disabled)
- **Private clusters** only (no public API endpoints)
- **Customer-managed KMS** encryption recommended
- **etcd encryption** available for data-at-rest protection
- **GovCloud API endpoints** (`api.openshiftusgov.com`, `sso.openshiftusgov.com`)

This guide focuses on the **operational controls** around the Terraform framework itself -- how to manage the code, prevent data leakage, and operate in restricted networks.

---

## Fork and Control the Repository

In a controlled environment, you should not pull directly from an upstream public repository. Instead:

### 1. Fork to Your Approved Source Control

Fork this repository into your organization's approved source control system (GitHub Enterprise, GitLab, Bitbucket, etc.).

```bash
# Clone the upstream repo
git clone https://github.com/supernovae/rosa-tf.git
cd rosa-tf

# Checkout the latest tagged release
LATEST_TAG=$(git describe --tags --abbrev=0)
git checkout "$LATEST_TAG"

# Push to your internal repository
git remote add internal https://git.your-org.example.com/platform/rosa-tf.git
git push internal "$LATEST_TAG"
git push internal main
```

### 2. Pin to a Tagged Release

Always deploy from a tagged release rather than `main`:

```bash
# Clone and checkout the latest release automatically
git clone https://github.com/supernovae/rosa-tf.git
cd rosa-tf
git checkout $(git describe --tags --abbrev=0)

# Or pin a specific version explicitly
git clone --branch v1.2.0 https://git.your-org.example.com/platform/rosa-tf.git
```

This ensures reproducibility and allows your change management process to approve specific versions.

### 3. Set Up Branch Protection

Configure your internal repository with:

- Require pull request reviews before merging
- Require status checks to pass (security scans, `terraform validate`)
- Restrict who can push to `main`
- Require signed commits (if your organization requires it)

### 4. Track Vulnerabilities

This repository includes automated security scanning:

- **Dependabot** alerts for dependency vulnerabilities
- **Trivy** SARIF results uploaded to the GitHub Security tab
- **Checkov** SARIF results for Terraform policy violations

Review these findings in your fork's **Security** tab. Adapt the GitHub Actions workflow (`.github/workflows/security.yml`) for your internal CI system as needed.

---

## Disable Terraform Telemetry

By default, Terraform sends anonymous usage data ("checkpoint") to HashiCorp to check for updates and collect crash reports. In a FedRAMP environment, you should disable this to prevent any outbound data transmission.

### Option A: Environment Variable

Set this in your shell profile, CI/CD pipeline, or automation wrapper:

```bash
export CHECKPOINT_DISABLE=1
```

### Option B: Terraform CLI Configuration

Create or update `~/.terraformrc` (Linux/macOS) or `%APPDATA%\terraform.rc` (Windows):

```hcl
disable_checkpoint = true
```

### Recommendation

Use **both** methods for defense-in-depth. Set the environment variable in your CI/CD pipeline configuration and the CLI config on all operator workstations.

---

## Security Scanning

This framework includes a comprehensive security scanning pipeline. See [SECURITY.md](SECURITY.md) for the full tool inventory, skipped checks, and compliance notes.

### Tools Summary

| Tool | Purpose | Scope |
|------|---------|-------|
| **Checkov** | Policy-as-code for Terraform | All `.tf` files |
| **Trivy** | Vulnerability and misconfiguration scanner | All Terraform config |
| **ShellCheck** | Shell script static analysis | All `.sh` files |
| **Gitleaks** | Secrets detection in Git history | Full repository |
| **TruffleHog** | Verified secrets detection | Full repository |

### Running Scans Locally

```bash
# Run all security checks
make security

# Individual scans
make security-terraform  # Checkov, Trivy
make security-shell      # ShellCheck
make security-secrets    # Gitleaks, pattern matching
```

### Adapting for Internal CI

The GitHub Actions workflow at `.github/workflows/security.yml` can be adapted for your internal CI system (Jenkins, GitLab CI, etc.). Key jobs to replicate:

1. `terraform-validate` -- Format check and validation across all 4 environments
2. `trivy` -- Terraform misconfiguration scanning (HIGH/CRITICAL)
3. `checkov` -- Policy-as-code checks with SARIF output
4. `shellcheck` -- Shell script analysis
5. `gitleaks` / `trufflehog` -- Secrets detection

**Recommendation:** Run `make security` as a mandatory gate before any `terraform apply` in your pipeline.

---

## Vendor Terraform Providers

In air-gapped or restricted networks, `terraform init` cannot reach the public Terraform Registry (`registry.terraform.io`). You must vendor (mirror) the required providers and configure Terraform to use your local or internal mirror.

### Required Providers

All modules in this framework use **local paths** (no external registry modules). Only the Terraform **providers** need to be mirrored:

| Provider | Source | Min Lock Version | Used For |
|----------|--------|------------------|----------|
| aws | `hashicorp/aws` | 6.28.0 | VPC, IAM, Route53, S3, KMS |
| rhcs | `terraform-redhat/rhcs` | 1.7.2 | ROSA cluster lifecycle via OCM API |
| kubernetes | `hashicorp/kubernetes` | 3.0.1 | Namespaces, ServiceAccounts, Secrets, ConfigMaps |
| kubectl | `alekc/kubectl` | 2.1.3 | CRD-based resources (Subscriptions, ArgoCD, LokiStack) |
| external | `hashicorp/external` | 2.3.5 | OAuth token retrieval (bootstrap only) |
| null | `hashicorp/null` | 3.2.4 | Validation preconditions |
| time | `hashicorp/time` | 0.13.1 | Operator readiness waits |
| random | `hashicorp/random` | 3.8.1 | Password generation, unique suffixes |
| tls | `hashicorp/tls` | 4.2.0 | VPN certificate generation |
| local | `hashicorp/local` | 2.6.2 | VPN config file output |

> **Note:** Versions shown are the minimum found across committed `.terraform.lock.hcl` files. Lock files contain cryptographic hashes for integrity verification and should be preserved in your fork. Individual environments may pin newer patch versions -- always run `terraform providers` to see the exact versions for your environment.

### Step 1: Mirror Providers (Internet-Connected Machine)

On a machine with internet access, download the providers to a local directory:

```bash
# From an environment directory (e.g., environments/govcloud-classic)
terraform providers mirror /path/to/provider-mirror

# Or mirror for a specific platform
terraform providers mirror \
  -platform=linux_amd64 \
  /path/to/provider-mirror
```

This creates a directory structure like:

```
provider-mirror/
├── registry.terraform.io/
│   ├── alekc/
│   │   └── kubectl/
│   ├── hashicorp/
│   │   ├── aws/
│   │   ├── external/
│   │   ├── kubernetes/
│   │   ├── local/
│   │   ├── null/
│   │   ├── random/
│   │   ├── time/
│   │   └── tls/
│   └── terraform-redhat/
│       └── rhcs/
```

### Step 2: Transfer to Air-Gapped Environment

Transfer the `provider-mirror/` directory to your restricted environment using your approved data transfer process (secure file transfer, approved media, etc.).

### Step 3: Configure Terraform to Use Local Mirror

Create or update `~/.terraformrc` on the air-gapped machine:

**Option A: Filesystem Mirror (simplest)**

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/opt/terraform/provider-mirror"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

**Option B: Network Mirror (shared across team)**

If you host an internal HTTP mirror (e.g., Artifactory, Nexus, or a simple HTTP server):

```hcl
provider_installation {
  network_mirror {
    url = "https://terraform-mirror.your-org.example.com/"
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

### Step 4: Initialize and Verify

```bash
cd environments/govcloud-classic
terraform init

# Verify providers loaded from mirror (no registry.terraform.io traffic)
terraform version
terraform providers
```

### Keeping Providers Updated

When upgrading provider versions:

1. Update version constraints in your fork
2. Re-run `terraform providers mirror` on an internet-connected machine
3. Transfer updated providers to the air-gapped environment
4. Run `terraform init -upgrade` to update lock files
5. Commit updated `.terraform.lock.hcl` files

### Verifying Your Provider Inventory

Use these commands to audit which providers and versions are in use. This is useful after upgrades or when preparing a vendor mirror for a new environment.

**List providers for a specific environment:**

```bash
cd environments/govcloud-classic
terraform providers
```

**Audit pinned versions across all environments from lock files:**

```bash
# Extract provider versions from all lock files
for lockfile in environments/*/.terraform.lock.hcl; do
  echo "=== $(dirname "$lockfile") ==="
  grep -A1 'provider "' "$lockfile" | grep -E 'provider|version' | paste - - | \
    sed 's/.*provider "//;s/".*//' | while read -r provider; do
      version=$(grep -A2 "provider \"$provider\"" "$lockfile" | grep 'version' | head -1 | sed 's/.*= "//;s/"//')
      printf "  %-40s %s\n" "$provider" "$version"
    done
done
```

**Quick check -- compare lock file providers to this table:**

```bash
# List all unique providers from lock files
grep 'provider "' environments/*/.terraform.lock.hcl | \
  sed 's/.*provider "//;s/".*//' | sort -u
```

If the output includes providers not listed in the table above, update the table and re-run `terraform providers mirror` to include them in your vendor mirror.

---

## Terraform Identity and Security Controls

This section documents how the Terraform framework satisfies specific NIST 800-53 controls for FedRAMP High authorization.

### AC-6: Least Privilege

Terraform uses a dedicated Kubernetes ServiceAccount (`terraform-operator`) with `cluster-admin` privileges. While cluster-admin is broad, it is the minimum required because Terraform:

- Installs operators across multiple namespaces (OLM subscriptions)
- Creates CRDs and custom resources (ArgoCD, LokiStack, DPA)
- Manages cluster-scoped RBAC bindings
- Configures monitoring and logging infrastructure

**Mitigations:**
- The SA lives in a dedicated `rosa-terraform` namespace (not `kube-system` or any user namespace), providing clear separation of automation identity from system and workload resources
- The dedicated namespace avoids ROSA's managed admission webhooks on system namespaces, enabling full Terraform lifecycle management (create, rotate, destroy) without platform workarounds
- No human identity uses this SA -- it is Terraform-only
- Token is not cached in-process; it exists only in encrypted Terraform state
- All operations are logged in OpenShift API server audit logs with identity `system:serviceaccount:rosa-terraform:terraform-operator`

### AU-3: Audit Evidence

Every Terraform apply generates auditable evidence in the OpenShift API server logs:

- **User identity:** `system:serviceaccount:rosa-terraform:terraform-operator`
- **User-Agent:** `Terraform/<version> hashicorp/kubernetes/<version>` (or `kubectl-provider`)
- **Action:** Create, Update, Patch, Delete for each resource
- **Resource:** Full API path (e.g., `/apis/operators.coreos.com/v1alpha1/namespaces/openshift-operators/subscriptions`)

To enable detailed request body logging (recommended for FedRAMP):

```yaml
apiVersion: config.openshift.io/v1
kind: APIServer
metadata:
  name: cluster
spec:
  audit:
    profile: WriteRequestBodies
```

Additionally, the SHA256 hash of each applied template is deterministic and can serve as a configuration baseline:

```bash
# Generate audit evidence for applied configuration
terraform show -json | jq '.values.root_module.child_modules[].resources[] | select(.type | startswith("kubectl_manifest")) | {type, name, values: (.values.yaml_body | @base64d | sha256)}'
```

### SC-28: Protection of Information at Rest

Terraform state contains the ServiceAccount token (marked `sensitive = true`). State MUST be stored on encrypted S3:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "rosa/terraform.tfstate"
  region         = "us-gov-west-1"
  encrypt        = true              # SSE-S3 minimum
  kms_key_id     = "alias/tf-state"  # SSE-KMS recommended
  dynamodb_table = "terraform-locks"
}
```

**Requirements:**
- S3 bucket: `aws:kms` or `AES256` server-side encryption
- S3 bucket policy: Restrict `s3:GetObject` to authorized IAM roles
- DynamoDB lock table: Encrypted at rest
- No local state files in production

### CM-3: Configuration Change Control

All infrastructure changes flow through Terraform:

1. Code changes are reviewed via pull request
2. `terraform plan` shows the diff before apply
3. `terraform apply` executes with full audit logging
4. State is versioned (S3 versioning recommended)
5. Rollback: `terraform apply` with previous code version

No manual `oc` or `kubectl` commands are needed for managed resources. The Terraform state is the source of truth for all GitOps layer configuration.

### Credential Lifecycle

| Credential | Scope | Storage | Rotation |
|---|---|---|---|
| SA token | cluster-admin (K8s) | Terraform state (encrypted S3) | `terraform apply -replace` |
| htpasswd admin | cluster-admin (OAuth) | RHCS API (encrypted) | `terraform apply` with new password |
| RHCS token/credentials | OCM API | Environment variables | Per organizational policy |
| AWS credentials | IAM | Environment variables or instance profile | Per organizational policy |

---

## FedRAMP Configuration Checklist

Verify these settings in your GovCloud `.tfvars` files before deploying:

### Mandatory Controls

| Setting | Required Value | tfvars Variable | Notes |
|---------|---------------|-----------------|-------|
| FIPS Mode | `true` | `fips` | Enforced by GovCloud env defaults |
| Private Cluster | `true` | `private_cluster` | No public API endpoint |
| GovCloud Region | `us-gov-west-1` or `us-gov-east-1` | `aws_region` | Must be a GovCloud region |

### Strongly Recommended

| Setting | Recommended Value | tfvars Variable | Notes |
|---------|-------------------|-----------------|-------|
| Cluster KMS | `"create"` | `cluster_kms_mode` | Customer-managed encryption keys |
| Infrastructure KMS | `"create"` | `infra_kms_mode` | Separate key for infrastructure |
| etcd Encryption | `true` | `etcd_encryption` | Additional data-at-rest encryption |
| VPC Flow Logs | `true` | `enable_vpc_flow_logs` | Network traffic logging for audit |

### Example: FedRAMP-Compliant tfvars

```hcl
# Mandatory
fips            = true
private_cluster = true
aws_region      = "us-gov-west-1"

# Encryption
cluster_kms_mode = "create"
infra_kms_mode   = "create"
etcd_encryption  = true

# Audit and monitoring
enable_vpc_flow_logs = true
```

> **Note:** The `environments/govcloud-classic/prod.tfvars` and `environments/govcloud-hcp/prod.tfvars` files already include these settings. Review them as a starting point for your deployment.

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [Security Scanning](SECURITY.md) | Security tools, skipped checks, compliance notes |
| [Zero-Egress Clusters](ZERO-EGRESS.md) | Air-gapped cluster deployment, operator mirroring |
| [GovCloud Classic](../environments/govcloud-classic/README.md) | GovCloud Classic environment details |
| [GovCloud HCP](../environments/govcloud-hcp/README.md) | GovCloud HCP environment details |
| [Operations Guide](OPERATIONS.md) | Day-to-day operations, troubleshooting |
| [OIDC Configuration](OIDC.md) | Identity provider configuration |

### External References

- [FedRAMP Hybrid Cloud Console](https://console.openshiftusgov.com)
- [ROSA GovCloud Guide](https://cloud.redhat.com/experts/rosa/rosa-govcloud/)
- [Terraform Provider Mirror Documentation](https://developer.hashicorp.com/terraform/cli/commands/providers/mirror)
- [Terraform CLI Configuration](https://developer.hashicorp.com/terraform/cli/config/config-file)
- [NIST 800-53 Security Controls](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
