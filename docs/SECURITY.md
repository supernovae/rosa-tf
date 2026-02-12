# Security Scanning Configuration

This document explains the security scanning tools used in this project, their configurations, and justifications for any filtered or skipped checks.

## Table of Contents

- [Overview](#overview)
- [Security Tools](#security-tools)
- [Skipped Checks](#skipped-checks)
- [Running Security Scans](#running-security-scans)
- [Pre-commit Hooks](#pre-commit-hooks)
- [CI/CD Integration](#cicd-integration)

---

## Overview

This project uses multiple security scanning tools to ensure:
- No hardcoded secrets or credentials
- Terraform configurations follow security best practices
- Shell scripts are safe from injection vulnerabilities
- IAM policies follow least-privilege principles

**Current Status:** 320 Checkov checks pass, 22 expected failures (documented below).

---

## Security Tools

### Terraform Security

| Tool | Purpose | Configuration |
|------|---------|---------------|
| **Checkov** | Policy-as-code for Terraform | `.checkov.yml` |
| **tfsec** | Static analysis for Terraform | Default config |
| **Trivy** | Vulnerability scanner | HIGH/CRITICAL severity |
| **TFLint** | Terraform linter | `.tflint.hcl` |

### Shell Script Security

| Tool | Purpose | Configuration |
|------|---------|---------------|
| **ShellCheck** | Shell script static analysis | `-x -e SC1091` |
| **Bashate** | Shell style checker | Ignore E006 (line length) |

### Secrets Detection

| Tool | Purpose | Configuration |
|------|---------|---------------|
| **Gitleaks** | Git history secrets scan | `.gitleaks.toml` |
| **TruffleHog** | Verified secrets detection | `--only-verified` |
| **detect-secrets** | Pre-commit secrets scan | `.secrets.baseline` |

---

## Skipped Checks

### Checkov Skipped Checks

| Check ID | Description | Justification |
|----------|-------------|---------------|
| `CKV_AWS_144` | Ensure S3 bucket has cross-region replication enabled | **Not applicable for ROSA.** ROSA clusters are single-region deployments. Cross-region replication would conflict with data residency requirements for GovCloud/FedRAMP workloads. Backup/DR is handled by OADP with customer-configured backup locations. |
| `CKV_AWS_145` | Ensure S3 bucket is encrypted with KMS CMK | **Handled differently.** We use `cluster_kms_mode` and `infra_kms_mode` variables to allow users to choose between provider-managed (AWS managed keys) and customer-managed KMS keys. For GovCloud, customer-managed keys are enforced by default. |
| `CKV_AWS_124` | Ensure CloudFormation stacks send event notifications to SNS | **Not applicable.** CloudFormation stacks are Terraform-managed wrappers used solely for `DeletionPolicy: Retain` on S3 buckets (Loki logs, OADP backups). Terraform controls all stack lifecycle events. SNS notifications add no operational value for these ephemeral infrastructure stacks. |

### Checkov Expected Failures (Documented)

These checks fail by design due to ROSA/OpenShift requirements:

| Check ID | Description | Resources | Justification |
|----------|-------------|-----------|---------------|
| `CKV_AWS_111` | IAM policies allow write access without constraints | KMS policies, OADP policy | **Required by ROSA.** KMS key policies must allow `kms:*` for the key owner and specific encrypt/decrypt permissions for ROSA roles. OADP requires write access to S3 for backup operations. Resources are constrained by ARN, not action. |
| `CKV_AWS_356` | IAM policies allow "*" as resource for restrictable actions | KMS policies, OADP policy | **Required by ROSA.** KMS policies use `Resource: "*"` per AWS KMS policy syntax - the policy is attached to the key itself, so the resource is implicit. OADP S3 permissions are scoped to specific buckets. |
| `CKV_AWS_109` | IAM policies allow permissions management without constraints | KMS policies | **Required for KMS key management.** ROSA requires ability to manage key grants for EBS encryption. This is scoped to specific keys, not all KMS resources. |
| `CKV_AWS_382` | Security groups allow egress to 0.0.0.0:0 on all ports | Jumphost, VPN, ECR endpoints | **Required for functionality.** Jumphost needs outbound access to cluster API, package repos, and AWS services. VPN security group manages client traffic. ECR endpoints need to respond to requests. Ingress is restricted. |
| `CKV_AWS_136` | ECR repositories not encrypted with KMS | ECR repository | **User configurable.** ECR encryption is configurable via `kms_key_arn` variable. Defaults to AES-256 (AWS-managed) for simplicity. Users can enable KMS encryption by providing a key ARN. |
| `CKV_AWS_51` | ECR image tags are mutable | ECR repository | **User configurable.** Tag mutability is configurable via `image_tag_mutability` variable. Defaults to MUTABLE for development convenience. Users should set to IMMUTABLE for production. |

### tfsec Known Issues

| Issue | Description | Justification |
|-------|-------------|---------------|
| `check` block unsupported | tfsec errors on Terraform 1.5+ `check` blocks | **Tool limitation.** tfsec doesn't support Terraform 1.5+ native check blocks. We use `--soft-fail` to prevent blocking. Consider migrating to Trivy which has better Terraform support. |

### ShellCheck Skipped Checks

| Check ID | Description | Justification |
|----------|-------------|---------------|
| `SC1091` | Not following sourced files | **Build environment variability.** Our scripts may source files that don't exist in the scanning environment but are present at runtime (e.g., Terraform-generated scripts). |

### Gitleaks Allowlist

The following patterns are allowlisted in `.gitleaks.toml`:

| Pattern | Justification |
|---------|---------------|
| `<your-.*>` | Placeholder tokens in documentation |
| `YOUR_.*_HERE` | Placeholder values in examples |
| `sha256~[xX]+` | Redacted token examples |
| `example.com` | Example domain names |

---

## Running Security Scans

### Quick Commands

```bash
# Run all security checks
make security

# Run specific checks
make security-shell      # ShellCheck only
make security-terraform  # Checkov, tfsec, trivy
make security-secrets    # Gitleaks, pattern matching

# Run pre-commit hooks (includes security)
make pre-commit
```

### Manual Commands

```bash
# Checkov (full scan)
checkov -d . --framework terraform

# ShellCheck (all scripts)
find . -name "*.sh" -type f | xargs shellcheck -x -e SC1091

# Gitleaks
gitleaks detect --source . --config .gitleaks.toml

# tfsec
tfsec . --soft-fail

# Trivy
trivy config . --severity HIGH,CRITICAL
```

---

## Pre-commit Hooks

Pre-commit hooks run automatically on `git commit`. Install with:

```bash
pip install pre-commit
pre-commit install
```

### Hooks Enabled

| Hook | Tool | Purpose |
|------|------|---------|
| `shellcheck` | ShellCheck | Shell script analysis |
| `bashate` | Bashate | Shell style |
| `terraform_fmt` | Terraform | Format check |
| `terraform_validate` | Terraform | Syntax validation |
| `terraform_tflint` | TFLint | Linting |
| `terraform_trivy` | Trivy | Security scan |
| `detect-secrets` | detect-secrets | Secrets in staged files |
| `gitleaks` | Gitleaks | Secrets in commits |
| `check-yaml` | pre-commit | YAML syntax |
| `check-json` | pre-commit | JSON syntax |

### Bypassing Hooks (Emergency Only)

```bash
# Skip pre-commit (not recommended)
git commit --no-verify -m "message"
```

---

## CI/CD Integration

GitHub Actions runs security checks on all PRs and pushes to `main`.

### Workflow: `.github/workflows/security.yml`

| Job | Tools | Scope |
|-----|-------|-------|
| `shellcheck` | ShellCheck | All `*.sh` files |
| `tfsec` | tfsec | All Terraform |
| `trivy` | Trivy | Config scanning |
| `checkov` | Checkov | All Terraform |
| `gitleaks` | Gitleaks | Git history |
| `trufflehog` | TruffleHog | Verified secrets |
| `terraform-validate` | Terraform | All 4 environments |
| `yaml-lint` | yamllint | All YAML files |

### SARIF Integration

Security findings are uploaded to GitHub Security tab via SARIF format:
- tfsec results
- Trivy results
- Checkov results

---

## Adding New Checks

When adding new security checks:

1. **Test locally first:**
   ```bash
   make security
   ```

2. **If check fails with false positive:**
   - Document the justification in this file
   - Add to skip list with comment explaining why
   - Update CI configuration if needed

3. **Never skip checks without documentation.**

---

## Compliance Notes

### FedRAMP Alignment

For GovCloud deployments, this project enforces:

- **Customer-managed KMS keys** by default (`cluster_kms_mode = "create"`, `infra_kms_mode = "create"`)
- **Private clusters** only (no public API endpoints)
- **FIPS-enabled** OpenShift builds
- **Encryption at rest** for all data stores

### Audit Trail

All security scan results are:
- Logged in CI/CD (GitHub Actions)
- Uploaded to GitHub Security tab (SARIF)
- Available locally via `make security`

---

## OADP Backup Credentials

When OADP (backup/restore) is enabled, a Kubernetes Secret is created to configure AWS authentication. This project uses **IRSA (IAM Roles for Service Accounts)** rather than static AWS credentials.

### How IRSA Works for OADP

```
┌─────────────────────────────────────────────────────────────────┐
│                    OADP Authentication Flow                      │
├─────────────────────────────────────────────────────────────────┤
│  1. Terraform creates IAM role with OIDC trust policy           │
│  2. Trust policy scopes role to OADP service accounts only      │
│  3. cloud-credentials Secret contains role ARN (not keys!)      │
│  4. Velero pods request token from OpenShift OIDC               │
│  5. AWS STS validates token, issues temporary credentials       │
│  6. Credentials expire in ~1 hour, auto-renewed                 │
└─────────────────────────────────────────────────────────────────┘
```

### Security Benefits

| Feature | IRSA (Used) | Static Credentials |
|---------|-------------|-------------------|
| Credential lifetime | ~1 hour (auto-rotated) | Until manually rotated |
| Scope | OADP pods only | Anyone with secret access |
| Rotation required | No (automatic) | Yes (manual) |
| Credential in secret | Role ARN reference | Actual AWS keys |
| Blast radius if leaked | Limited (short-lived) | Full (until rotated) |

### What's in the Secret

The `cloud-credentials` secret in `openshift-adp` namespace contains:

```ini
[default]
sts_regional_endpoints = regional
role_arn = arn:aws:iam::123456789:role/cluster-name-oadp-role
web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
```

**This is NOT sensitive data** - it only tells Velero which role to assume. The actual authentication happens via OIDC tokens that are:
- Generated per-pod
- Short-lived (~1 hour)
- Validated by AWS STS

### IAM Role Trust Policy

The IAM role created by Terraform only trusts specific OIDC subjects:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/OIDC_ENDPOINT"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "OIDC_ENDPOINT:sub": [
        "system:serviceaccount:openshift-adp:openshift-adp-controller-manager",
        "system:serviceaccount:openshift-adp:velero"
      ]
    }
  }
}
```

### Why Not Static Credentials?

Static AWS credentials would:
- Require manual rotation procedures
- Risk exposure if the secret is leaked
- Work from anywhere (not just the cluster)
- Not align with ROSA STS-mode best practices

IRSA ensures backup credentials can only be used by authorized OADP pods running on the cluster.

---

## Resources

- [Checkov Documentation](https://www.checkov.io/5.Policy%20Index/aws.html)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Gitleaks Configuration](https://github.com/gitleaks/gitleaks#configuration)
- [tfsec Checks](https://aquasecurity.github.io/tfsec/latest/checks/aws/)
- [Trivy Misconfiguration](https://aquasecurity.github.io/trivy/latest/docs/scanner/misconfiguration/)
