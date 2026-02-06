# ROSA Terraform - Multi-Environment Framework

Deploy Red Hat OpenShift Service on AWS (ROSA) across Commercial and GovCloud environments with Classic or Hosted Control Plane (HCP) cluster types.

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
export TF_VAR_aws_region=$AWS_REGION

# GovCloud
export AWS_REGION=us-gov-west-1      # or us-gov-east-1
export TF_VAR_aws_region=$AWS_REGION
```

**3. ROSA Login**
```bash
# Commercial
rosa login --use-auth-code

# GovCloud
rosa login --govcloud --token="<your_token_from_console.opnshiftusgov.com_here>"
```

**4. Get OCM Token and Set Environment Variable**

| Environment | Token URL |
|-------------|-----------|
| Commercial | https://console.redhat.com/openshift/token/show |
| GovCloud | https://console.openshiftusgov.com/openshift/token |

```bash
# Copy token from URL above, then:
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
terraform init && terraform plan -var-file=dev.tfvars

# GovCloud Classic (FedRAMP)
cd environments/govcloud-classic
terraform init && terraform plan -var-file=dev.tfvars
```

### Deploy HCP Clusters

> **Prerequisite:** Complete [HCP Account Roles](#hcp-account-roles-required-before-hcp-clusters) setup first.

```bash
# Commercial HCP (~15 min provisioning)
cd environments/commercial-hcp
terraform init && terraform plan -var-file=dev.tfvars

# GovCloud HCP (FedRAMP)
cd environments/govcloud-hcp
terraform init && terraform plan -var-file=dev.tfvars
```

If account roles are missing, Terraform will detect this and show instructions to create them.

## Environments

| Environment | Type | Security | Guide |
|-------------|------|----------|-------|
| [commercial-classic](environments/commercial-classic/) | Classic | Configurable | [README](environments/commercial-classic/README.md) |
| [commercial-hcp](environments/commercial-hcp/) | HCP | Configurable | [README](environments/commercial-hcp/README.md) |
| [govcloud-classic](environments/govcloud-classic/) | Classic | FIPS, Private, KMS mandatory | [README](environments/govcloud-classic/README.md) |
| [govcloud-hcp](environments/govcloud-hcp/) | HCP | FIPS, Private, KMS mandatory | [README](environments/govcloud-hcp/README.md) |

Each environment includes `dev.tfvars` (single-AZ, cost-optimized) and `prod.tfvars` (multi-AZ, HA).

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

This framework includes optional GitOps integration for Day 2 operations via OpenShift GitOps (ArgoCD).

**Key Principles:**
- **Infrastructure-focused**: Deploys cluster operators and platform services, not user workloads
- **No secrets in GitOps**: Credentials and secrets are managed by Terraform/AWS, never in Git
- **Terraform-to-GitOps bridge**: Uses ConfigMaps to pass Terraform-managed values (S3 buckets, KMS keys, etc.) to GitOps-deployed operators

**Included Layers:**
- Web Terminal - Browser-based cluster access
- OADP (Velero) - Backup/restore with Terraform-provisioned S3
- OpenShift Virtualization - KubeVirt for VM workloads

```hcl
# Enable in your tfvars
install_gitops             = true
enable_layer_terminal      = true
enable_layer_oadp          = true
enable_layer_virtualization = false
```

📖 **[GitOps Documentation](gitops-layers/README.md)** - Architecture, layer details, and customization

## Repository Structure

```
├── environments/
│   ├── commercial-classic/    # AWS Commercial + Classic
│   ├── commercial-hcp/        # AWS Commercial + HCP
│   ├── govcloud-classic/      # GovCloud + Classic (FedRAMP)
│   └── govcloud-hcp/          # GovCloud + HCP (FedRAMP)
│
├── modules/
│   ├── networking/            # VPC, Jump Host, Client VPN
│   ├── security/              # KMS, IAM (Classic + HCP)
│   ├── cluster/               # ROSA clusters, Machine Pools
│   ├── ingress/               # Custom ingress controllers
│   └── gitops-layers/         # Day 2 operations via ArgoCD
│
├── gitops-layers/             # ArgoCD manifests (Kustomize)
└── docs/                      # Operations guide, Roadmap
```

## Prerequisites

**Required:**
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) >= 1.4.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
- [ROSA CLI](https://docs.openshift.com/rosa/cli_reference/rosa_cli/rosa-get-started-cli.html) >= 1.2.39
- [OpenShift CLI (oc)](https://docs.openshift.com/rosa/cli_reference/openshift_cli/getting-started-cli.html)

**Optional (recommended for GitOps):**
- [jq](https://jqlang.github.io/jq/download/) - JSON processor for parsing API responses. Used by GitOps layers to retrieve OAuth tokens when running locally. The scripts have fallback parsing without jq, but jq improves reliability.

## OCM Token Management

**Never store tokens in Terraform files or version control.**

Tokens expire periodically. If you see authentication errors during `terraform plan` or `apply`:

```bash
# Refresh your token from the appropriate URL:
# Commercial: https://console.redhat.com/openshift/token/show
# GovCloud:   https://console.openshiftusgov.com/openshift/token

# Then update the environment variable:
export TF_VAR_ocm_token="your-new-token"

# Re-login to ROSA CLI as well:
rosa login --use-auth-code  # Commercial
rosa login --govcloud --token="<your_token_from_console.opnshiftusgov.com_here> # GovCloud
```

## Deployment

### Deploy a Cluster

```bash
cd environments/<environment>

# Development (single-AZ, cost-optimized)
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

# Production (multi-AZ, HA)
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

### Access Private Clusters

Private clusters (all GovCloud, prod Commercial) require VPN or jump host access.

**Jump Host (SSM) - Included by default:**
```bash
aws ssm start-session --target $(terraform output -raw jumphost_instance_id)

# From jump host
oc login $(terraform output -raw api_url) \
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

```bash
cd environments/<environment>
terraform destroy -var-file=dev.tfvars
```

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
| Single-AZ (dev) | 3x m5.xlarge | 2x r5.xlarge | 2x m5.xlarge | **7 nodes** |
| Multi-AZ (prod) | 3x m5.xlarge | 3x r5.xlarge | 3x m5.xlarge | **9 nodes** |

**Classic Single-AZ Cost Breakdown (~$1,100/mo):**
| Component | Instances | Cost |
|-----------|-----------|------|
| Control Plane | 3x m5.xlarge | ~$420/mo |
| Infra Nodes | 2x r5.xlarge | ~$370/mo |
| Workers | 2x m5.xlarge | ~$280/mo |
| NAT Gateway | 1x | ~$35/mo |

**Classic Multi-AZ Cost Breakdown (~$1,500/mo):**
| Component | Instances | Cost |
|-----------|-----------|------|
| Control Plane | 3x m5.xlarge | ~$420/mo |
| Infra Nodes | 3x r5.xlarge | ~$550/mo |
| Workers | 3x m5.xlarge | ~$420/mo |
| NAT Gateways | 3x (1 per AZ) | ~$100/mo |

### ROSA HCP Architecture

HCP control plane is always multi-AZ (managed by Red Hat). You only pay for worker nodes in your account.

| Component | Default |
|-----------|---------|
| Control Plane | Red Hat managed (multi-AZ) |
| Workers | 2x m5.xlarge |
| Total in Account | **2 nodes** |

**HCP Default Cost Breakdown (~$440/mo):**
| Component | Cost |
|-----------|------|
| HCP Control Plane Fee | ~$125/mo |
| Workers (2x m5.xlarge) | ~$280/mo |
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
make security  # Runs tfsec, checkov, trivy
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run `make test` (lint, security, validate)
4. Submit a pull request

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
