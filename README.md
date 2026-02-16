# ROSA Terraform - Multi-Environment Framework

<!-- Versioning -->
[![Latest Tag](https://img.shields.io/github/v/tag/supernovae/rosa-tf)](https://github.com/supernovae/rosa-tf/tags)
[![Latest Release](https://img.shields.io/github/release/supernovae/rosa-tf)](https://github.com/supernovae/rosa-tf/releases)

<!-- Terraform & ROSA -->
![Terraform Version](https://img.shields.io/badge/Terraform-%3E%3D%201.6-623CE4?logo=terraform)
![AWS Provider](https://img.shields.io/badge/AWS%20Provider-%3E%3D%205.0-orange?logo=amazon-aws)
![ROSA](https://img.shields.io/badge/ROSA-HCP%20%7C%20Classic-red?logo=red-hat)

<!-- Security Posture -->
![Trivy IaC](https://img.shields.io/badge/Trivy-IaC%20Scanning-blue?logo=aqua)
[![Security Checks](https://github.com/supernovae/rosa-tf/actions/workflows/security.yml/badge.svg)](https://github.com/supernovae/rosa-tf/actions/workflows/security.yml)
[![Dependabot](https://img.shields.io/badge/Dependabot-enabled-brightgreen?logo=dependabot)](https://github.com/supernovae/rosa-tf/security)

<!-- GovCloud & Compliance Signals -->
[![GovCloud Safe](https://img.shields.io/badge/GovCloud-Safe-success)](docs/FEDRAMP.md)
[![Reproducible Builds](https://img.shields.io/badge/Reproducible-Builds-blue)](docs/FEDRAMP.md#vendor-terraform-providers)
[![Telemetry Disabled](https://img.shields.io/badge/Telemetry-Disabled-lightgrey)](docs/FEDRAMP.md#disable-terraform-telemetry)

<!-- CI -->
[![Release Workflow](https://github.com/supernovae/rosa-tf/actions/workflows/release.yml/badge.svg)](https://github.com/supernovae/rosa-tf/actions/workflows/release.yml)

Deploy Red Hat OpenShift Service on AWS (ROSA) across Commercial and GovCloud environments with Classic or Hosted Control Plane (HCP) cluster types.

## Getting Started

```bash
# Clone the repository
git clone https://github.com/supernovae/rosa-tf.git
cd rosa-tf

# Checkout the latest tagged release (recommended for production)
git checkout $(git describe --tags --abbrev=0)
```

> **Tip:** Pin to a tagged release for stability. Check [Releases](https://github.com/supernovae/rosa-tf/releases) for the latest version. Use `git tag -l` to list available tags, or pin a specific version with `git checkout v1.2.0`.

## Quick Start

### Prerequisites Setup (Required for All Environments)

Before deploying any cluster, complete these steps:

**1. AWS Login**
```bash
# Commercial AWS
aws configure
# Or use SSO
aws sso login --profile your-profile

# GovCloud
aws configure --profile govcloud
export AWS_PROFILE=govcloud
```

**2. Set AWS Region**
```bash
# Commercial
export AWS_REGION=us-east-1          # or us-west-2, etc.

# GovCloud
export AWS_REGION=us-gov-west-1      # or us-gov-east-1
```

> **Note:** The `aws_region` is set in your `.tfvars` file, not via environment variable. The `AWS_REGION` export above is for the AWS CLI and ROSA CLI only.

**3. ROSA Login**
```bash
# Commercial
rosa login --use-auth-code

# GovCloud
rosa login --govcloud --token="<your_token_from_console.openshiftusgov.com_here>"
```

**4. Set RHCS Authentication**

**Commercial AWS** -- uses service account (client ID + client secret):

1. Create a service account at [console.redhat.com/iam/service-accounts](https://console.redhat.com/iam/service-accounts)
2. Assign **OpenShift Cluster Manager** permissions at [console.redhat.com/iam/user-access/users](https://console.redhat.com/iam/user-access/users)
3. Save the client secret immediately -- it is only shown once

```bash
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"
```

> **Note:** The offline OCM token is deprecated for commercial cloud. Service accounts are the recommended method for workstation and CI/CD use.

**GovCloud** -- uses offline OCM token:

```bash
# Get token from: https://console.openshiftusgov.com/openshift/token
export TF_VAR_ocm_token="your-offline-token-here"

# Clear any conflicting environment variables
unset RHCS_TOKEN RHCS_URL
```

**5. Verify Setup**
```bash
aws sts get-caller-identity
rosa whoami
rosa verify quota
```

### HCP Account Roles (Required Before HCP Clusters)

> **Skip this section** if deploying Classic clusters only.

HCP clusters require **account-level IAM roles** that are shared across all HCP clusters in an AWS account. These must exist **before** deploying your first HCP cluster.

**Option A: Use Terraform (Recommended - manage roles as code)**
```bash
cd environments/account-hcp

# Commercial AWS
terraform init
terraform apply -var-file=commercial.tfvars

# GovCloud
terraform apply -var-file=govcloud.tfvars
```

**Option B: Use ROSA CLI**
```bash
# Commercial
rosa create account-roles --hosted-cp --mode auto

# GovCloud  
rosa create account-roles --hosted-cp --mode auto
```

> **Note:** Unlike Classic clusters (where IAM roles are created/destroyed with each cluster), HCP account roles persist independently and are reused across clusters. See [IAM Lifecycle Management](docs/IAM-LIFECYCLE.md) for details.

### Deploy Classic Clusters

```bash
# Commercial Classic
cd environments/commercial-classic
terraform init
terraform plan  -var-file=cluster-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars

# GovCloud Classic (FedRAMP)
cd environments/govcloud-classic
terraform init
terraform plan  -var-file=cluster-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars
```

### Deploy HCP Clusters

> **Prerequisite:** Complete [HCP Account Roles](#hcp-account-roles-required-before-hcp-clusters) setup first.

```bash
# Commercial HCP (~15 min provisioning)
cd environments/commercial-hcp
terraform init
terraform plan  -var-file=cluster-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars

# GovCloud HCP (FedRAMP)
cd environments/govcloud-hcp
terraform init
terraform plan  -var-file=cluster-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars
```

If account roles are missing, Terraform will detect this and show instructions to create them.

## Environments

| Environment | Type | Security | Guide |
|-------------|------|----------|-------|
| [commercial-classic](environments/commercial-classic/) | Classic | Configurable | [README](environments/commercial-classic/README.md) |
| [commercial-hcp](environments/commercial-hcp/) | HCP | Configurable | [README](environments/commercial-hcp/README.md) |
| [govcloud-classic](environments/govcloud-classic/) | Classic | FIPS, Private, KMS mandatory | [README](environments/govcloud-classic/README.md) |
| [govcloud-hcp](environments/govcloud-hcp/) | HCP | FIPS, Private, KMS mandatory | [README](environments/govcloud-hcp/README.md) |

Each environment includes split tfvars for the two-phase deployment pattern:
- `cluster-dev.tfvars` / `cluster-prod.tfvars` -- Phase 1: cluster provisioning (`install_gitops = false`)
- `gitops-dev.tfvars` / `gitops-prod.tfvars` -- Phase 2: GitOps overlay (`install_gitops = true`, stacked on top of cluster tfvars)

## Regional Limitations

Some AWS regions have limited availability zone support which affects ROSA deployment options:

| Region | AZs | Classic Single-AZ | Classic Multi-AZ | HCP Single-AZ | HCP Multi-AZ |
|--------|-----|-------------------|------------------|---------------|--------------|
| us-east-1, us-west-2 | 4+ | ✅ | ✅ | ✅ | ✅ |
| us-east-2, eu-west-1 | 3 | ✅ | ✅ | ✅ | ✅ |
| **us-west-1** | **2** | ✅ | ❌ | ❌ | ❌ |
| us-gov-west-1 | 3 | ✅ | ✅ | ✅ | ✅ |
| us-gov-east-1 | 3 | ✅ | ✅ | ✅ | ✅ |

**Notes:**
- **Multi-AZ requires 3+ AZs** for proper control plane and worker distribution
- **us-west-1**: HCP is NOT available (no ETA); use Classic single-AZ only
- AZs like `us-east-1e` are auto-filtered (don't support NAT Gateway/common instance types)

If you attempt an unsupported deployment, Terraform will show a helpful error message with alternatives.

## Classic vs HCP

| Feature | Classic | HCP |
|---------|---------|-----|
| Control Plane | Customer nodes | Red Hat managed |
| Provisioning | ~45 minutes | ~15 minutes |
| IAM Policies | Customer managed | AWS managed |
| Account Roles | 4 (cluster-scoped) | 3 (account-level, shared) |
| IAM Lifecycle | Created/destroyed with cluster | Persist independently |
| Spot Instances | ✅ Supported | ❌ Not supported |
| Version Drift | Independent | Machine pools n-2 of CP |

> **HCP IAM Note:** HCP account roles must exist before deploying HCP clusters. See [HCP Account Roles](#hcp-account-roles-required-before-hcp-clusters).

## GitOps Integration (Optional)

This framework includes optional GitOps integration for Day 2 operations via OpenShift GitOps (ArgoCD). GitOps layers are applied in a **separate phase** after cluster provisioning using stacked tfvars.

**Key Principles:**
- **Two-phase deployment**: Phase 1 creates the cluster (`cluster-*.tfvars`), Phase 2 applies GitOps layers (`gitops-*.tfvars` overlay)
- **Infrastructure-focused**: Deploys cluster operators and platform services, not user workloads
- **No secrets in GitOps**: Credentials and secrets are managed by Terraform/AWS, never in Git
- **Native Terraform providers**: All Kubernetes resources are managed via `hashicorp/kubernetes` and `alekc/kubectl` -- no shell scripts or `local-exec`
- **Dedicated Service Account**: A `terraform-operator` ServiceAccount with cluster-admin is created during Phase 2 for long-term state management

**Included Layers:**
- Web Terminal - Browser-based cluster access
- OADP (Velero) - Backup/restore with Terraform-provisioned S3
- OpenShift Virtualization - KubeVirt for VM workloads
- Cert-Manager - Automated TLS with Let's Encrypt DNS01 + custom IngressController
- Monitoring (Loki + Grafana) - Centralized log aggregation

See [Deployment](#deployment) for the two-phase workflow, or the full **[GitOps Documentation](gitops-layers/README.md)** for architecture, layer details, and customization.

## Repository Structure

```
├── environments/
│   ├── account-hcp/             # HCP account-level IAM roles
│   ├── commercial-classic/      # AWS Commercial + Classic
│   ├── commercial-hcp/          # AWS Commercial + HCP
│   ├── govcloud-classic/        # GovCloud + Classic (FedRAMP)
│   └── govcloud-hcp/            # GovCloud + HCP (FedRAMP)
│       ├── cluster-dev.tfvars   # Phase 1: cluster provisioning
│       ├── gitops-dev.tfvars    # Phase 2: GitOps overlay
│       ├── cluster-prod.tfvars  # Phase 1: production cluster
│       └── gitops-prod.tfvars   # Phase 2: production GitOps
│
├── modules/
│   ├── networking/              # VPC, Jump Host, Client VPN
│   ├── security/                # KMS, IAM (Classic + HCP)
│   ├── cluster/                 # ROSA clusters, Machine Pools
│   └── gitops-layers/           # Day 2 operations (native providers)
│       ├── operator/            # Kubernetes manifests (kubectl_manifest)
│       ├── certmanager/         # IAM + Route53 for cert-manager
│       ├── oadp/                # IAM + S3 for Velero backups
│       ├── monitoring/          # IAM + S3 for Loki log storage
│       └── virtualization/      # Resource configuration
│
├── gitops-layers/layers/        # YAML templates for kubectl_manifest
└── docs/                        # Operations, FedRAMP, Roadmap
```

## Prerequisites

**Required:**
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) >= 1.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
- [ROSA CLI](https://docs.openshift.com/rosa/cli_reference/rosa_cli/rosa-get-started-cli.html) >= 1.2.39
- [OpenShift CLI (oc)](https://docs.openshift.com/rosa/cli_reference/openshift_cli/getting-started-cli.html) -- for cluster access and verification

> **Note:** GitOps layers use native Terraform providers (`kubernetes`, `kubectl`) and do not require `jq`, `curl`, or shell scripts.

## RHCS Authentication

**Never store credentials in Terraform files or version control.**

### Commercial AWS (Service Accounts)

Commercial environments use RHCS service accounts for authentication. Service account credentials do not expire, making them ideal for CI/CD pipelines and automation.

If you see authentication errors during `terraform plan` or `apply`:
1. Verify your service account exists at [console.redhat.com/iam/service-accounts](https://console.redhat.com/iam/service-accounts)
2. Verify it has **OpenShift Cluster Manager** permissions
3. If the secret was lost, delete and recreate the service account

```bash
# Set credentials
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"

# Re-login to ROSA CLI
rosa login --use-auth-code
```

### GovCloud (Offline Token)

GovCloud environments continue to use offline OCM tokens. Tokens expire periodically and must be refreshed.

```bash
# Refresh token from: https://console.openshiftusgov.com/openshift/token
export TF_VAR_ocm_token="your-new-token"

# Clear conflicting variables
unset RHCS_TOKEN RHCS_URL

# Re-login to ROSA CLI
rosa login --govcloud --token="<your_token_from_console.openshiftusgov.com_here>"
```

## Deployment

### Phase 1: Create a Cluster

```bash
cd environments/<environment>

# Development (single-AZ, cost-optimized)
terraform init
terraform plan  -var-file=cluster-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars

# Production (multi-AZ, HA)
terraform plan  -var-file=cluster-prod.tfvars
terraform apply -var-file=cluster-prod.tfvars
```

### Phase 2: Apply GitOps Layers (Optional)

After the cluster is provisioned, apply the GitOps overlay by stacking both tfvars files. The gitops tfvars sets `install_gitops = true` and enables layers.

```bash
# Development
terraform plan  -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars

# Production
terraform plan  -var-file=cluster-prod.tfvars -var-file=gitops-prod.tfvars
terraform apply -var-file=cluster-prod.tfvars -var-file=gitops-prod.tfvars
```

> **Note:** The gitops tfvars overrides `install_gitops = true` and layer flags on top of the cluster tfvars. Both files must be passed together so all cluster configuration remains consistent. See [Operations Guide](docs/OPERATIONS.md) for full details.

### Access Private Clusters

Private clusters (all GovCloud, prod Commercial) require VPN or jump host access.

**Jump Host (SSM) - Included by default:**
```bash
aws ssm start-session --target $(terraform output -raw jumphost_instance_id)

# From jump host
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)
```

**Client VPN - Optional:**
```bash
# Enable in tfvars
create_client_vpn = true

# Apply then download config
terraform apply -var-file=prod.tfvars
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn
```

### Destroy a Cluster

If GitOps layers were applied (Phase 2), destroy with both tfvars so the Kubernetes provider has the real API URL:

```bash
cd environments/<environment>
terraform destroy -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars
```

If GitOps was **never applied**, destroy with just the cluster tfvars:

```bash
terraform destroy -var-file=cluster-dev.tfvars
```

> **Note:** All GitOps resources (SA, CRBs, namespaces) are fully deletable -- no manual `state rm` steps needed. The `rosa-terraform` namespace and `openshift-gitops` are both allowed by ROSA's webhook. To remove individual layers while keeping the cluster, disable them in the gitops tfvars and re-apply. See [Operations Guide](docs/OPERATIONS.md) for details.

## Features

| Feature | Description |
|---------|-------------|
| **VPC** | Multi-AZ with NAT/TGW/Proxy egress options |
| **IAM** | Account roles, operator roles, OIDC provider |
| **KMS** | Three modes: provider-managed, create, or existing |
| **Jump Host** | SSM-enabled EC2 for private cluster access |
| **Client VPN** | Optional OpenVPN-compatible VPN |
| **Machine Pools** | GPU, high memory, spot instances (Classic) |
| **GitOps Layers** | Day 2 operations via ArgoCD |

## KMS Encryption Modes

Two separate KMS keys with **strict separation** for blast radius containment:

| Key | Purpose | Used For |
|-----|---------|----------|
| **Cluster KMS** | ROSA resources ONLY | Worker EBS, etcd encryption |
| **Infrastructure KMS** | Non-ROSA resources ONLY | Jump host, CloudWatch, S3/OADP, VPN |

### Mode Options

| Mode | Commercial | GovCloud | Description |
|------|------------|----------|-------------|
| `provider_managed` | ✅ DEFAULT | ❌ | AWS managed `aws/ebs` key |
| `create` | ✅ | ✅ DEFAULT | Terraform creates customer-managed key |
| `existing` | ✅ | ✅ | Use your own KMS key ARN |

> **⚠️ FedRAMP Compliance Warning**
>
> In GovCloud, this module defaults to customer-managed KMS keys to align with FedRAMP Moderate/High expectations.
> Supplying an AWS-managed key (e.g., `aws/ebs`) may not satisfy FedRAMP key-management controls.
> If you choose to do so, you are responsible for documenting and justifying compliance exceptions with your 3PAO.

### Commercial Configuration

```hcl
# dev.tfvars - Use AWS default encryption (simplest)
cluster_kms_mode = "provider_managed"
infra_kms_mode   = "provider_managed"
etcd_encryption  = false

# prod.tfvars - Customer-managed keys
cluster_kms_mode = "create"
infra_kms_mode   = "create"
etcd_encryption  = true
```

### GovCloud Configuration

```hcl
# All GovCloud environments - Customer-managed required
cluster_kms_mode = "create"  # or "existing" with your key ARN
infra_kms_mode   = "create"  # or "existing" with your key ARN
etcd_encryption  = true
```


### Bring Your Own Key

```hcl
# Use existing keys from centralized key management
cluster_kms_mode    = "existing"
cluster_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/..."

infra_kms_mode    = "existing"
infra_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/..."
```

### Key Separation Benefits

- **Blast radius containment**: Cluster key compromise doesn't affect infrastructure
- **Independent rotation**: Different rotation policies for each key
- **Simplified audit**: Clear separation in CloudTrail logs
- **Compliance**: Meets FedRAMP and security framework requirements

## Cost Estimates

### ROSA Classic Architecture

Classic clusters run control plane and infrastructure nodes in your account:

| Configuration | Control Plane | Infra Nodes | Workers | Total Nodes |
|---------------|---------------|-------------|---------|-------------|
| Single-AZ (dev) | 3x m6i.xlarge | 2x r5.xlarge | 2x m6i.xlarge | **7 nodes** |
| Multi-AZ (prod) | 3x m6i.xlarge | 3x r5.xlarge | 3x m6i.xlarge | **9 nodes** |

**Classic Single-AZ Cost Breakdown (~$1,100/mo):**
| Component | Instances | Cost |
|-----------|-----------|------|
| Control Plane | 3x m6i.xlarge | ~$420/mo |
| Infra Nodes | 2x r5.xlarge | ~$370/mo |
| Workers | 2x m6i.xlarge | ~$280/mo |
| NAT Gateway | 1x | ~$35/mo |

**Classic Multi-AZ Cost Breakdown (~$1,500/mo):**
| Component | Instances | Cost |
|-----------|-----------|------|
| Control Plane | 3x m6i.xlarge | ~$420/mo |
| Infra Nodes | 3x r5.xlarge | ~$550/mo |
| Workers | 3x m6i.xlarge | ~$420/mo |
| NAT Gateways | 3x (1 per AZ) | ~$100/mo |

### ROSA HCP Architecture

HCP control plane is always multi-AZ (managed by Red Hat). You only pay for worker nodes in your account.

| Component | Default |
|-----------|---------|
| Control Plane | Red Hat managed (multi-AZ) |
| Workers | 2x m6i.xlarge |
| Total in Account | **2 nodes** |

**HCP Default Cost Breakdown (~$440/mo):**
| Component | Cost |
|-----------|------|
| HCP Control Plane Fee | ~$125/mo |
| Workers (2x m6i.xlarge) | ~$280/mo |
| NAT Gateway | ~$35/mo |

> **Note:** Scale workers based on workload needs. Add NAT gateways for multi-AZ VPC (~$65/mo more).

### Summary

| Architecture | Classic (Single-AZ) | Classic (Multi-AZ) | HCP |
|--------------|---------------------|--------------------|----|
| Nodes in Account | 7 | 9 | **2** |
| Monthly Cost | ~$1,100 | ~$1,500 | **~$440** |
| Savings vs Classic | — | — | **60-70%** |

> **Note:** HCP is significantly cheaper due to no control plane or infra nodes in your account.
> Prices based on us-east-1 on-demand rates. Excludes data transfer, additional machine pools, EBS storage, and VPN costs (~$116/mo if enabled).

## Documentation

| Document | Description |
|----------|-------------|
| [Operations Guide](docs/OPERATIONS.md) | Day-to-day operations, troubleshooting, credentials |
| [FedRAMP Guide](docs/FEDRAMP.md) | FedRAMP deployment, telemetry, provider vendoring |
| [Security Scanning](docs/SECURITY.md) | Security tools, skipped checks, compliance notes |
| [Roadmap](docs/ROADMAP.md) | Feature status and planned work |
| [Client VPN](modules/networking/client-vpn/README.md) | VPN setup and costs |
| [Machine Pools (Classic)](modules/cluster/machine-pools/README.md) | GPU, spot, autoscaling |
| [Machine Pools (HCP)](modules/cluster/machine-pools-hcp/README.md) | HCP-specific pools |
| [GitOps Layers](gitops-layers/README.md) | Day 2 operations |

## Security

### Pre-commit Hooks

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

### Security Scanning

```bash
make security  # Runs checkov, trivy, shellcheck, gitleaks
```

## Contributing

1. Fork the repository
2. Create a feature branch from `main`
3. Run `make test` (lint, security, validate)
4. Submit a pull request

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed guidelines.

## License

Apache 2.0 - See [LICENSE](LICENSE) for details.

## References

- [ROSA Documentation](https://docs.openshift.com/rosa/welcome/index.html)
- [ROSA GovCloud Guide](https://cloud.redhat.com/experts/rosa/rosa-govcloud/)
- [RHCS Terraform Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest)
- [Commercial Console](https://console.redhat.com)
- [GovCloud Console](https://console.openshiftusgov.com)

---

## Acknowledgments

Built with ❤️ using [Cursor](https://cursor.sh/).

This project was developed with AI assistance. In accordance with Red Hat's [guidance on AI-assisted development](https://www.redhat.com/en/blog/ai-assisted-development-and-open-source-navigating-legal-issues), we disclose this to maintain transparency and trust within the open source community. All AI-generated contributions have been reviewed, tested, and validated by human maintainers.
