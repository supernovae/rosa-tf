# FedRAMP Deployment Guide

This guide covers how to deploy and operate this ROSA Terraform framework in a FedRAMP-controlled environment. It is intended for organizations operating under **FedRAMP High**, **DoD IL4/IL5**, **NIST 800-53**, or similar regulatory controls.

## Table of Contents

- [Overview](#overview)
- [Fork and Control the Repository](#fork-and-control-the-repository)
- [Disable Terraform Telemetry](#disable-terraform-telemetry)
- [Security Scanning](#security-scanning)
- [Vendor Terraform Providers](#vendor-terraform-providers)
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

# Pin to a tagged release
git checkout v1.0.1

# Push to your internal repository
git remote add internal https://git.your-org.example.com/platform/rosa-tf.git
git push internal v1.0.1
git push internal main
```

### 2. Pin to a Tagged Release

Always deploy from a tagged release rather than `main`:

```bash
git clone --branch v1.0.1 https://git.your-org.example.com/platform/rosa-tf.git
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

| Provider | Source | Pinned Version |
|----------|--------|----------------|
| aws | `hashicorp/aws` | 6.28.0+ |
| rhcs | `terraform-redhat/rhcs` | 1.7.2 |
| external | `hashicorp/external` | 2.3.5 |
| null | `hashicorp/null` | 3.2.4 |
| time | `hashicorp/time` | 0.13.1 |
| random | `hashicorp/random` | 3.8.1 |
| tls | `hashicorp/tls` | 4.2.1 |
| local | `hashicorp/local` | 2.6.2 |

> **Note:** Pinned versions are from the committed `.terraform.lock.hcl` files. These lock files contain cryptographic hashes for integrity verification and should be preserved in your fork.

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
│   ├── hashicorp/
│   │   ├── aws/
│   │   ├── external/
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
