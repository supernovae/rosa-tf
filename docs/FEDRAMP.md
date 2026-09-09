# FedRAMP Deployment Guide

This guide covers how to deploy and operate this ROSA Terraform framework in a FedRAMP-controlled environment. It is intended for organizations operating under **FedRAMP High**, **DoD IL4/IL5**, **NIST 800-53**, or similar regulatory controls.

## Virtual machine workloads

The [Virtualization guide](VIRTUALIZATION.md) requires explicit vendor support
confirmation for the exact GovCloud architecture, release and storage combination.
Shared HCP/Classic inputs do not establish support or extend an authorization
boundary. Disable public boot-image imports until approved mirrors are ready;
review guest hardening/patching, console RBAC, private migration traffic and
application-consistent recovery. NetApp retained volumes/snapshots and AWS
encryption are safeguards, not standalone evidence of FIPS validation or FedRAMP
compliance. Include guest images, FSx, backup accounts/regions and KMS permissions
in the system security plan and test recovery before production.

## Application and VM recovery

For [EFS shared files](EFS-STORAGE.md), explicitly authorize worker security groups,
use encrypted access-point mounts and test AWS Backup recovery in the approved
region. Access-point/network isolation is not per-pod IAM authentication. Review
tenant boundaries, KMS/vault permissions and retained data costs; neither TLS nor
the layer itself establishes FedRAMP or FIPS compliance.

The [OADP guide](OADP.md) covers explicit workload scope, paused schedules,
short-lived STS credentials, private AWS connectivity and isolated VM restore
acceptance. Protect repository passwords and KMS recovery permissions outside
the source cluster. Record backup RPO/RTO evidence, recovery-copy account/region
boundaries and operator approvals in the system security plan. Encryption,
versioning and this configuration do not by themselves establish compliance.
Object Lock and cross-account replication require a separate reviewed design;
do not expire shared Kopia chunks by object age. OpenShift 4.18 is blocked by
the current OADP support gate; do not bypass it for GovCloud deployments.

## Table of Contents

- [Overview](#overview)
- [Virtual machine workloads](#virtual-machine-workloads)
- [Application and VM recovery](#application-and-vm-recovery)
- [GovCloud HCP zero-egress default](#govcloud-hcp-zero-egress-default)
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

## GovCloud HCP zero-egress default

For **new GovCloud HCP clusters**, this repository defaults `zero_egress = true`.
Classic retains its supported controlled-egress architecture. This is our
defense-in-depth design choice, not a claim that FedRAMP mandates this feature or
that enabling it grants an authorization.

The rationale maps to **SC-7 (Boundary Protection)** and **SC-7(5)
(Deny by Default / Allow by Exception)**: remove general public outbound routes
and retain explicitly required private service paths. This reduces public
exfiltration paths and the operational burden of maintaining public destination
allowlists. It supports, but does not by itself satisfy, these controls. See
[NIST SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final).

Red Hat describes zero-egress-ready HCP as a foundation that must be combined
with customer routing and egress controls; setting the cluster property alone
does not block public traffic. See [Red Hat's architecture guidance](https://cloud.redhat.com/experts/rosa/best-practices-recommendations/).

In our managed VPC, the default omits NAT, IGW and public subnets, uses S3 and
regional interface endpoints, and limits the new endpoint security group to
HTTPS from the VPC CIDR. Endpoint policies still need organizational tailoring:
private connectivity alone does not stop access to unauthorized AWS resources.
For BYO VPCs, the network owner must validate endpoints, private DNS, route
tables, peering/TGW paths and any alternate internet access.

Document the following in the system security plan and deployment evidence:

- Approved endpoint destinations, IAM/resource policies and data-flow boundaries.
- Tested denial of public outbound access and successful required private flows.
- Private Git, image registry, identity, update and operator-mirroring paths.
- Logging, vulnerability scanning, image provenance and patch procedures.
- Any exception (`zero_egress = false`), its mission need, owner, compensating
  controls and review date.

**Existing clusters:** explicitly preserve `zero_egress = false` until an approved
migration or replacement. Adopting the new default may remove NAT/routes from
Terraform-managed networks. Do not apply it blindly to existing state. The
cluster property is not evidence of a supported in-place conversion. See the
[zero-egress deployment guide](ZERO-EGRESS.md).

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
git clone --branch v1.1.0 https://git.your-org.example.com/platform/rosa-tf.git
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
- **tfsec** SARIF results uploaded to the GitHub Security tab
- **Grype** SARIF results uploaded to the GitHub Security tab
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
| **tfsec** | Terraform misconfiguration scanner | All `.tf` files |
| **Grype** | Vulnerability scanner (SCA) | Full repository |
| **ShellCheck** | Shell script static analysis | All `.sh` files |
| **Gitleaks** | Secrets detection in Git history | Full repository |
| **TruffleHog** | Verified secrets detection | Full repository |

### Running Scans Locally

```bash
# Run all security checks
make security

# Individual scans
make security-terraform  # Checkov, tfsec, Grype
make security-shell      # ShellCheck
make security-secrets    # Gitleaks, pattern matching
```

### Adapting for Internal CI

The GitHub Actions workflow at `.github/workflows/security.yml` can be adapted for your internal CI system (Jenkins, GitLab CI, etc.). Key jobs to replicate:

1. `terraform-validate` -- Format check and validation across all 4 environments
2. `tfsec` -- Terraform misconfiguration scanning (HIGH/CRITICAL)
3. `grype` -- Vulnerability scanning (HIGH/CRITICAL)
4. `checkov` -- Policy-as-code checks with SARIF output
5. `shellcheck` -- Shell script analysis
6. `gitleaks` / `trufflehog` -- Secrets detection

**Recommendation:** Run `make security` as a mandatory gate before any `terraform apply` in your pipeline.

---

## Vendor Terraform Providers

In air-gapped or restricted networks, `terraform init` cannot reach the public Terraform Registry (`registry.terraform.io`). You must vendor (mirror) the required providers and configure Terraform to use your local or internal mirror.

### Required Providers

All modules in this framework use **local paths** (no external registry modules). Only the Terraform **providers** need to be mirrored:

| Provider | Source | Verified Version | Used For |
|----------|--------|------------------|----------|
| aws | `hashicorp/aws` | 6.63.0 | VPC, IAM, Route53, S3, KMS |
| rhcs | `terraform-redhat/rhcs` | 1.7.7 | ROSA cluster lifecycle via OCM API |
| kubernetes | `hashicorp/kubernetes` | 3.2.1 | Namespaces, ServiceAccounts, Secrets, ConfigMaps |
| kubectl | `alekc/kubectl` | 2.4.1 | CRD-based resources (Subscriptions, ArgoCD, LokiStack) |
| external | `hashicorp/external` | 2.4.1 | OAuth token retrieval (bootstrap only) |
| null | `hashicorp/null` | 3.3.1 | Validation preconditions |
| time | `hashicorp/time` | 0.14.1 | Operator readiness waits |
| random | `hashicorp/random` | 3.9.0 | Password generation, unique suffixes |
| tls | `hashicorp/tls` | 4.4.0 | VPN certificate generation |
| local | `hashicorp/local` | 2.9.0 | VPN config file output |

> **Note:** These are the verified stable selections as of September 8, 2026. All four cluster environments share identical lockfiles, including macOS ARM64 and Linux AMD64 checksums. Preserve the lockfiles and use `terraform init -lockfile=readonly`; see [provider upgrade notes](PROVIDER-UPGRADE.md).

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
2. On a connected machine, run `terraform init -backend=false -upgrade` in each root and refresh platform checksums as described in [provider upgrade notes](PROVIDER-UPGRADE.md)
3. Validate and review the selections, then commit the updated `.terraform.lock.hcl` files
4. Run `terraform providers mirror` from each root using those lockfiles and transfer the mirror and lockfiles through your approved process
5. Initialize restricted runners with `terraform init -lockfile=readonly`

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

### Certificate automation

Use the Red Hat cert-manager operator from an approved catalog and record the
installed CSV/operand versions as evidence. The layer defaults to supported
Certificate/IngressController integration, short-lived STS credentials, TXT-only
zone-scoped DNS writes and explicit private-key rotation. The community Routes
controller is opt-in and requires a reviewed image digest. Do not enable an
OpenShift Technology Preview feature gate solely for certificate integration.

The bundled public ACME issuers are not compatible with the zero-egress HCP
default. An internal CA design needs private issuer/trust configuration outside
this public-ACME layer; preserve network boundaries. Review the
[cert-manager deployment and migration guide](../modules/gitops-layers/certmanager/README.md)
for catalog approvals, DNS resolvers, lifecycle monitoring and support limits.

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

Record template hashes with the Git commit as a source baseline (not proof of the rendered or applied configuration). Avoid exporting raw Terraform state into audit logs: it contains credentials.

```bash
# Run from the repository root; retain the commit and template checksums.
git rev-parse HEAD
git ls-files -z '*.tftpl' | xargs -0 shasum -a 256
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
  use_lockfile   = true
}
```

**Requirements:**
- S3 bucket: `aws:kms` or `AES256` server-side encryption
- S3 bucket policy: Restrict `s3:GetObject` to authorized IAM roles
- S3 `.tflock` object: Allow GetObject, PutObject, and DeleteObject on the exact lock key
- No local state files in production

### CM-3: Configuration Change Control

All infrastructure changes flow through Terraform:

1. Code changes are reviewed via pull request
2. `terraform plan` shows the diff before apply
3. `terraform apply` executes with full audit logging
4. State is versioned (S3 versioning recommended)
5. Rollback: `terraform apply` with previous code version

No manual `oc` or `kubectl` commands are needed for managed resources. The Terraform state is the source of truth for all GitOps layer configuration.

### GitOps workload boundary (AC-3, AC-6, CM-3, SC-8)

The [GitOps layer](GITOPS.md) separates the privileged Terraform platform runner
from namespace-delegated Argo CD reconciliation. It defaults to SSO with explicit
group access, verified TLS, no local admin, no permanent runner token, and manual
workload sync with pruning off. AppProjects restrict repositories, destinations and
resource kinds; the built-in default project grants no deployment permissions.
Automatic sync requires an immutable reviewed commit, but commit pinning is not
signature verification or an approval system. Enforce those in the Git workflow.

For GovCloud, use approved private repositories/catalogs, reviewed outbound paths,
secret-store credentials and auditable promotion. Namespace delegation is not a
hostile-tenant isolation boundary. Validate RBAC denials, SSO claims, network policy,
restore and alerting in the actual cluster and retain evidence. These controls
support a system security plan; neither product compatibility nor these defaults
establishes FedRAMP authorization or FIPS validation for the complete deployment.

### Credential Lifecycle

The [NetApp layer](NETAPP-STORAGE.md) uses separate FSx/SVM credentials, trusted
ONTAP REST certificates, worker-bounded storage ingress and explicit retained
storage policies. The old `netapp_enable_fips` input was removed because it never
configured Trident. Validate actual cryptographic modules and data-in-transit
requirements: management TLS, KMS at rest and iSCSI CHAP are different controls;
they do not make ordinary NFS/iSCSI traffic encrypted or establish an authorization.
Maintain evidence for volume backups, isolated restores, access denials and
credential/certificate renewal; do not treat local snapshots as independent backups.

| Credential | Scope | Storage | Rotation |
|---|---|---|---|
| Short-lived runner token (preferred) | Privileged Terraform platform management | Secret-managed runner environment; protect plan/state artifacts | Renew via approved TokenRequest/IdP workflow before expiry |
| Legacy SA Secret (opt-in only) | cluster-admin (K8s) | Terraform state (encrypted S3) and Kubernetes Secret | Migrate/rotate using independent authorized credentials; never revoke the active apply credential |
| htpasswd bootstrap admin | cluster-admin (OAuth) | RHCS-managed IDP; generated password also in Terraform state | Verify production IdP/runner access, then explicitly retire bootstrap IDP; changing Terraform password does not rotate creation-only credentials |
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

### Observability evidence and recovery

Treat observability as an operated service, not just an installed operator.
The [observability guide](OBSERVABILITY.md) covers namespace-scoped access,
dashboards, tested alert delivery and ARM cost assessment for HCP. The
[AWS recovery guide](OBSERVABILITY-AWS-RECOVERY.md) separates configuration,
Loki data and historical metrics protection, including measured RPO/RTO drills.

For 4.18, confirm Logging/Loki 6.2 EUS coverage; do not upgrade to the expired 6.4
stream solely because its API is compatible. Mirror approved operator bundles
and all architectures before enabling observability on zero-egress HCP. Private
S3/STS connectivity still requires least-privilege IAM, bucket and endpoint policies.

Loki query retention is not immutable evidence retention: versioned S3 objects
can remain after compactor deletion. Obtain system-owner approval for physical
retention, key custody, archive access and deletion. Optional protected copies
stay within the approved AWS partition; recovery and notification destinations
must not silently create an unapproved external data path. These practices can
support AU-9/AU-11 and CP-9/CP-10 evidence under
[NIST SP 800-53 Rev. 5](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final);
they do not establish control satisfaction or an ATO.

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
