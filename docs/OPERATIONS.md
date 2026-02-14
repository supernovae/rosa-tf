# Operations Guide

Day-to-day operations, troubleshooting, and best practices for ROSA clusters.

## Table of Contents

- [Terraform State Management](#terraform-state-management)
- [Deployment Workflow](#deployment-workflow)
- [Credential Management](#credential-management)
- [Terraform Service Account Lifecycle](#terraform-service-account-lifecycle)
- [Cluster Access](#cluster-access)
- [Common Operations](#common-operations)
- [Client VPN Operations](#client-vpn-operations)
- [Troubleshooting](#troubleshooting)
- [Known Issues](#known-issues)

---

## Terraform State Management

By default, Terraform stores state locally in `terraform.tfstate`. For team collaboration and production use, store state remotely with locking.

### Why Remote State?

| Concern | Local State | Remote State (S3) |
|---------|-------------|-------------------|
| Team collaboration | ❌ Single user only | ✅ Shared access |
| State locking | ❌ No protection | ✅ DynamoDB locking |
| Backup/recovery | ❌ Manual | ✅ S3 versioning |
| Secrets in state | ⚠️ On disk | ✅ Encrypted at rest |
| CI/CD pipelines | ❌ State unavailable | ✅ Accessible |

### S3 Backend Setup

#### 1. Create S3 Bucket and DynamoDB Table

```bash
# Set your variables
BUCKET_NAME="your-org-terraform-state"
REGION="us-east-1"  # or us-gov-west-1 for GovCloud
DYNAMODB_TABLE="terraform-locks"

# Create S3 bucket with versioning
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION

aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION
```

#### 2. Configure Backend in Terraform

Create `backend.tf` in your environment directory:

```hcl
# environments/<environment>/backend.tf

terraform {
  backend "s3" {
    bucket         = "your-org-terraform-state"
    key            = "rosa/commercial-hcp/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**State Key Naming Convention:**

```
rosa/<environment>/<cluster-name>/terraform.tfstate

# Examples:
rosa/commercial-hcp/dev/terraform.tfstate
rosa/govcloud-classic/prod/terraform.tfstate
rosa/commercial-hcp/team-a-cluster/terraform.tfstate
```

#### 3. Initialize with Backend

```bash
# First time setup (migrates local state to S3)
cd environments/commercial-hcp
terraform init

# If you have existing local state
terraform init -migrate-state
```

### State Isolation Strategies

#### Per-Cluster State (Recommended)

Each cluster has its own state file. Best for:
- Independent cluster lifecycles
- Different teams managing different clusters
- Blast radius containment

```
s3://terraform-state/
├── rosa/commercial-hcp/dev/terraform.tfstate
├── rosa/commercial-hcp/staging/terraform.tfstate
├── rosa/commercial-hcp/prod/terraform.tfstate
├── rosa/govcloud-hcp/prod-east/terraform.tfstate
└── rosa/govcloud-hcp/prod-west/terraform.tfstate
```

#### Shared Account Resources

Account-level resources (HCP account roles) should have separate state:

```
s3://terraform-state/
├── rosa/account/commercial/terraform.tfstate    # Account roles
├── rosa/account/govcloud/terraform.tfstate      # Account roles
├── rosa/commercial-hcp/dev/terraform.tfstate    # Cluster
└── rosa/commercial-hcp/prod/terraform.tfstate   # Cluster
```

### Using Workspaces (Alternative)

Terraform workspaces allow multiple states in one configuration:

```bash
# Create workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Switch workspaces
terraform workspace select prod

# List workspaces
terraform workspace list

# Current workspace
terraform workspace show
```

**Note**: Workspaces share the same backend configuration. For strong isolation between environments, separate backend keys are preferred.

### Common State Operations

#### View State

```bash
# List all resources in state
terraform state list

# Show specific resource
terraform state show module.rosa_cluster.rhcs_cluster_rosa_hcp.this

# Show full state (caution: contains secrets)
terraform state pull
```

#### Move Resources

```bash
# Rename a resource in state
terraform state mv module.old_name module.new_name

# Move resource to different state file
terraform state mv -state-out=other.tfstate module.resource module.resource
```

#### Import Existing Resources

```bash
# Import existing VPC
terraform import module.vpc.aws_vpc.this vpc-0abc123def456

# Import existing ROSA cluster (not commonly needed)
terraform import 'module.rosa_cluster.rhcs_cluster_rosa_hcp.this' <cluster-id>
```

#### Remove from State (Without Destroying)

```bash
# Remove resource from Terraform management
terraform state rm module.resource.aws_instance.example

# The actual AWS resource still exists, just not managed by Terraform
```

### State Locking

DynamoDB provides state locking to prevent concurrent modifications.

```bash
# If lock is stuck (e.g., process crashed)
terraform force-unlock <LOCK_ID>

# Or via AWS CLI
aws dynamodb delete-item \
  --table-name terraform-locks \
  --key '{"LockID": {"S": "your-org-terraform-state/rosa/commercial-hcp/dev/terraform.tfstate"}}'
```

**Lock Info:**
```bash
# See who holds the lock
aws dynamodb get-item \
  --table-name terraform-locks \
  --key '{"LockID": {"S": "your-org-terraform-state/rosa/commercial-hcp/dev/terraform.tfstate"}}'
```

### GovCloud Considerations

For GovCloud, use GovCloud-specific bucket and table:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-org-terraform-state-govcloud"
    key            = "rosa/govcloud-hcp/prod/terraform.tfstate"
    region         = "us-gov-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**Note**: S3 bucket names must be globally unique. Use different buckets for Commercial and GovCloud to maintain separation.

### Sensitive Data in State

Terraform state contains sensitive values (passwords, tokens). Protect with:

1. **Encryption at rest**: S3 SSE (enabled above)
2. **Access control**: S3 bucket policies, IAM
3. **Audit logging**: S3 access logs, CloudTrail

```bash
# Check bucket encryption
aws s3api get-bucket-encryption --bucket $BUCKET_NAME

# Enable access logging (optional)
aws s3api put-bucket-logging \
  --bucket $BUCKET_NAME \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "your-access-logs-bucket",
      "TargetPrefix": "terraform-state/"
    }
  }'
```

### Best Practices Summary

| Practice | Recommendation |
|----------|----------------|
| State location | S3 with versioning + DynamoDB locking |
| Encryption | Always enable S3 SSE |
| State per cluster | Separate state files for isolation |
| Locking | Always use DynamoDB table |
| Access control | IAM policies restricting state bucket access |
| Backups | S3 versioning handles this automatically |
| CI/CD | Store backend config, not state, in git |

### Reference Documentation

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [State Locking](https://developer.hashicorp.com/terraform/language/state/locking)
- [State Management Commands](https://developer.hashicorp.com/terraform/cli/commands/state)
- [Sensitive Data in State](https://developer.hashicorp.com/terraform/language/state/sensitive-data)
- [Backend Configuration](https://developer.hashicorp.com/terraform/language/settings/backends/configuration)

---

## Deployment Workflow

### Environment Selection

| Environment | Use Case |
|-------------|----------|
| `commercial-classic` | Standard Commercial AWS with Classic architecture |
| `commercial-hcp` | Commercial AWS with faster HCP provisioning |
| `govcloud-classic` | FedRAMP workloads with Classic architecture |
| `govcloud-hcp` | FedRAMP workloads with HCP (~15 min deploy) |

### Deploy a Cluster (Two-Phase Workflow)

This codebase uses a **two-phase deployment** with stacked tfvars files:

- **Phase 1 (Cluster)**: Provisions the ROSA cluster, VPC, IAM, KMS, VPN, etc. GitOps is disabled (`install_gitops = false`).
- **Phase 2 (GitOps Layers)**: Applies the gitops overlay tfvars on top of the cluster tfvars. This enables `install_gitops = true` and configures the desired layers.

Each environment has paired tfvars files:

```
environments/<environment>/
├── cluster-dev.tfvars      # Phase 1: cluster infrastructure
├── gitops-dev.tfvars       # Phase 2: GitOps overlay (stacks on top)
├── cluster-prod.tfvars     # Phase 1: cluster infrastructure
└── gitops-prod.tfvars      # Phase 2: GitOps overlay (stacks on top)
```

Personal/named tfvars follow the same pattern (e.g., `byron-dev.tfvars` + `byron-dev-gitops.tfvars`).

```bash
# 1. Navigate to environment
cd environments/<environment>

# 2. Set credentials
# Commercial:
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"
# GovCloud:
# export TF_VAR_ocm_token="your-offline-token"
export AWS_REGION="us-east-1"  # or us-gov-west-1 for GovCloud

# 3. Phase 1: Create cluster (GitOps disabled by default in cluster tfvars)
terraform init
terraform plan -var-file=cluster-dev.tfvars
terraform apply -var-file=cluster-dev.tfvars
# Wait: 45-60 min (Classic) or 15-20 min (HCP)

# 4. For PRIVATE clusters: connect VPN before Phase 2
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn
sudo openvpn --config vpn-config.ovpn

# 5. Phase 2: Apply GitOps layers (stacked tfvars override install_gitops -> true)
terraform apply -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars
# GitOps installation: 2-5 min
```

**How Stacked Tfvars Work:**

The second `-var-file` overrides any variables defined in the first. The gitops overlay sets `install_gitops = true` and layer flags, while all cluster-level settings (name, region, compute, etc.) come from the cluster tfvars.

**Why Two Phases?**

| What Happens | Phase 1 Only | Phase 1 + Phase 2 |
|--------------|-------------|-------------------|
| Cluster creation | Works (AWS/ROSA APIs) | Already done |
| VPN creation | Works (AWS APIs only) | Already done |
| GitOps installation | Skipped (disabled) | Works (cluster in state, API reachable) |

This split solves two problems:
1. **Provider initialization**: The `kubernetes` provider needs a known cluster API URL. In Phase 1, `install_gitops = false` so the provider uses a dummy `localhost` and no K8s resources are created.
2. **Network connectivity**: GitOps requires authenticating to the cluster's OAuth server, which is only reachable from within the VPC for private clusters.

**GovCloud Note:** All GovCloud clusters are private by design (FedRAMP requirement). The two-phase approach is **mandatory** for GovCloud + GitOps.

### Using Make Shortcuts

```bash
# Quick deployment (Phase 1)
make commercial-classic-dev
make govcloud-hcp-prod

# Or with explicit variables
make plan ENV=commercial-hcp TFVARS=cluster-prod.tfvars
make apply ENV=govcloud-classic TFVARS=cluster-dev.tfvars

# Phase 2: GitOps layers
make apply ENV=commercial-hcp TFVARS="cluster-dev.tfvars -var-file=gitops-dev.tfvars"
```

### Destroy a Cluster (Complete Guide)

Follow this guide to completely destroy a cluster and clean up all resources.

#### Step 1: Navigate to Your Environment

```bash
cd environments/<environment>  # e.g., commercial-hcp, govcloud-classic
```

#### Step 2: Run Destroy

```bash
# Standard destroy - use only the cluster tfvars (install_gitops = false by default)
# This skips GitOps authentication, avoiding cluster connectivity issues
terraform destroy -var-file="cluster-dev.tfvars"
```

> **Why use only the cluster tfvars?** The cluster tfvars has `install_gitops = false`,
> so the kubernetes provider uses a dummy localhost host and no K8s resources are in scope.
> GitOps resources live inside the cluster and are automatically destroyed with the cluster.
> This avoids connectivity issues (especially for private clusters or when VPN is down).

#### Step 3: Clean Up Retained S3 Buckets

If you had monitoring or OADP enabled, S3 buckets are **retained** (not deleted) during
destroy to protect your log and backup data. During destroy, Terraform prints the bucket
names and cleanup commands.

When you are ready to delete the data:

```bash
# For each retained bucket (replace BUCKET_NAME with the name from destroy output)
BUCKET="dev-hcp-a3f7b2c1-loki-logs"

# Delete all objects and version markers
aws s3api delete-objects --bucket ${BUCKET} \
  --delete "$(aws s3api list-object-versions \
    --bucket ${BUCKET} \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# Then delete the empty bucket
aws s3 rb s3://${BUCKET}
```

> **Note:** You can keep the buckets as long as needed for compliance or auditing.
> S3 lifecycle rules will continue to expire old data per the retention settings.

#### Step 4: Verify Cleanup

After destroy completes:

```bash
# Check for retained S3 buckets
aws s3 ls | grep your-cluster-name

# Verify no orphaned resources
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*your-cluster-name*"
```

#### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `Token is empty` | GitOps trying to auth | Use only cluster tfvars (no gitops overlay) |
| `connection refused` | Cluster API unreachable | Use only cluster tfvars (no gitops overlay) |
| VPC deletion fails | Resources still attached | Wait 5 min, retry; check for orphaned ENIs |

#### Quick One-Liner

```bash
# Using only the cluster tfvars (install_gitops = false) handles everything
terraform destroy -var-file="cluster-dev.tfvars"
```

### Timing Expectations

| Operation | Classic | HCP |
|-----------|---------|-----|
| Cluster Create | 45-60 min | 15-20 min |
| Cluster Destroy | 15-20 min | 10-15 min |
| VPN Create | 15-20 min | 15-20 min |
| VPN Destroy | 15-25 min | 15-25 min |

---

## Credential Management

### AWS Credentials

| Type | Expiration | Best For |
|------|------------|----------|
| IAM User | Never | Long operations, CI/CD |
| SSO Session | 1-12 hours | Interactive use |
| Assumed Role | 15 min - 12 hours | Cross-account |

```bash
# Check credentials
aws sts get-caller-identity

# Extend STS session (up to 12 hours)
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/TerraformRole \
  --role-session-name rosa \
  --duration-seconds 43200
```

### RHCS Authentication

| Environment | Authentication | API Endpoint |
|-------------|---------------|--------------|
| Commercial | Service account (client_id + client_secret) | api.openshift.com |
| GovCloud | Offline OCM token | api.openshiftusgov.com |

**Commercial AWS (Service Account):**

```bash
# Set service account credentials
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"

# Verify connectivity
rosa login --use-auth-code
rosa whoami
```

Service account credentials do not expire, making them ideal for CI/CD.
Create at: https://console.redhat.com/iam/service-accounts

**GovCloud (Offline Token):**

```bash
# Set offline token from: https://console.openshiftusgov.com/openshift/token
export TF_VAR_ocm_token="your-offline-token"

# Clear conflicting variables
unset RHCS_TOKEN RHCS_URL

# Verify connectivity
rosa login --govcloud --token="$TF_VAR_ocm_token"
rosa whoami
```

**Token Expiration (GovCloud only):**
- Offline tokens expire after 30 days of inactivity
- Access tokens auto-refresh (~15 min lifetime)
- Enterprise IDP can configure custom lifetimes

**Switching Between Commercial and GovCloud:**

When switching between environments, always log out first to ensure a clean session:

```bash
# Log out of current environment
rosa logout

# Set credentials for target environment
# Commercial:
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"
# GovCloud:
# export TF_VAR_ocm_token="your-govcloud-token"

# Clear any cached environment variables
unset RHCS_TOKEN RHCS_URL

# Log in to new environment
rosa login --use-auth-code  # Commercial
# rosa login --govcloud --token="$TF_VAR_ocm_token"  # GovCloud

# Verify you're connected to the correct environment
rosa whoami
```

> **Important:** The `rosa` CLI caches session state. Failing to log out before switching environments can cause connectivity issues or operations against the wrong Hybrid Cloud Console.

---

## Terraform Service Account Lifecycle

After the initial cluster bootstrap, Terraform creates a Kubernetes ServiceAccount (`terraform-operator`) with a long-lived token for all subsequent operations. This replaces the OAuth-based authentication flow.

### Bootstrap Flow (First Apply)

1. `cluster_auth` module obtains OAuth token using htpasswd admin credentials
2. Kubernetes/kubectl providers use OAuth token to create cluster resources
3. `identity.tf` creates the ServiceAccount, ClusterRoleBinding, and token Secret
4. Token is stored in Terraform state (encrypted S3 at rest)
5. Output the token: `terraform output -raw terraform_sa_token`
6. Set in tfvars: `gitops_cluster_token = "<token>"`

### Subsequent Applies (SA Token)

Once `gitops_cluster_token` is set, Terraform uses the SA token directly:
- No OAuth flow, no htpasswd dependency
- Token is persistent (does not expire unless manually rotated)
- Identity appears in cluster audit logs as `system:serviceaccount:kube-system:terraform-operator`

### Rotating the SA Token

Auditors may require periodic token rotation. Because the token is managed by Terraform, rotation is a single command:

```bash
terraform apply -replace="module.gitops[0].kubernetes_secret_v1.terraform_operator_token"
```

This deletes the old Secret (immediately invalidating the token), creates a new one, and updates the Terraform state. After rotation:

1. Retrieve the new token: `terraform output -raw terraform_sa_token`
2. Update `gitops_cluster_token` in your tfvars
3. Verify: `terraform plan` should show no changes

### Removing the htpasswd IDP (Production Hardening)

After bootstrap, the htpasswd IDP can be removed to reduce the cluster's attack surface:

1. Set `create_admin_user = false` in your tfvars
2. Ensure `gitops_cluster_token` is set (SA token is the sole auth method)
3. Run `terraform apply` -- this removes the htpasswd IDP and cluster-admin group membership
4. Verify: `oc get oauth cluster -o yaml` should not list htpasswd

> **Note:** Do not remove htpasswd until you have verified the SA token works. Test with `terraform plan` using the SA token first.

### Destroy Workflow

With the two-phase tfvars approach, destruction is simple:

```bash
# Destroy using only the cluster tfvars (install_gitops = false)
# All K8s resources are skipped because the kubernetes provider uses dummy localhost
terraform destroy -var-file=cluster-prod.tfvars
```

For advanced cases where you need to explicitly remove K8s resources from state before destroying (e.g., during debugging), use `skip_k8s_destroy`:

```bash
# Step 1: Remove K8s resources from state (cluster still running)
terraform apply -var="skip_k8s_destroy=true" \
  -var-file=cluster-prod.tfvars -var-file=gitops-prod.tfvars

# Step 2: Destroy the cluster (no K8s resources left in state)
terraform destroy -var-file=cluster-prod.tfvars
```

---

## Cluster Access

### Direct Login (Public Clusters)

For public clusters or when you have network access (VPN/Direct Connect):

```bash
# One-liner using Terraform outputs
oc login $(terraform output -raw cluster_api_url) -u $(terraform output -raw cluster_admin_username) -p $(terraform output -raw cluster_admin_password)
```

### Jump Host (SSM)

All private clusters include a jump host with SSM access.

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw jumphost_instance_id)

# Connect
aws ssm start-session --target $INSTANCE_ID

# Login to cluster (from jump host)
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)
```

### Client VPN

Optional for extended access or web console.

```bash
# Enable in tfvars
create_client_vpn = true

# After apply, download config
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn

# Connect
sudo openvpn --config vpn-config.ovpn
```

**macOS DNS Fix:**
```bash
# If DNS doesn't work after VPN connect (use VPC DNS)
sudo networksetup -setdnsservers Wi-Fi 10.0.0.2

# After VPN disconnect, restore to automatic DNS
sudo networksetup -setdnsservers Wi-Fi empty
```

**Note:** Replace `Wi-Fi` with your network interface name (e.g., `Ethernet`, `USB 10/100/1000 LAN`). List interfaces with `networksetup -listallnetworkservices`.

### Public Clusters (Commercial dev)

```bash
# Direct access
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)

# Open console
open $(terraform output -raw cluster_console_url)
```

---

## Common Operations

### Scale Workers

```bash
# Edit tfvars
worker_node_count = 5

# Apply
terraform apply -var-file=dev.tfvars
```

### Add Machine Pool

```hcl
# Edit tfvars - add to machine_pools list
machine_pools = [
  {
    name          = "gpu"
    instance_type = "g4dn.xlarge"
    replicas      = 2
    labels        = { "node-role.kubernetes.io/gpu" = "" }
    taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  }
]
```

```bash
# Apply
terraform apply -var-file=prod.tfvars
```

See [Machine Pools Guide](MACHINE-POOLS.md) for GPU, bare metal, ARM/Graviton examples.

### Enable GitOps Layers

```bash
# Edit gitops-prod.tfvars to enable desired layers
install_gitops = true
enable_layer_terminal = true
enable_layer_oadp = true

# Apply with stacked tfvars (requires cluster access)
terraform apply -var-file=cluster-prod.tfvars -var-file=gitops-prod.tfvars
```

### Upgrade Cluster

Cluster upgrades differ between ROSA Classic and ROSA HCP architectures.

#### ROSA Classic Upgrades

Classic clusters upgrade as a single unit - control plane and workers upgrade together:

```bash
# 1. Check available versions
rosa list upgrade --cluster=<cluster-name>

# 2. Update tfvars with target version
openshift_version = "4.17.0"

# 3. If upgrading to a new minor version (e.g., 4.16 → 4.17), add acknowledgement
# This confirms you've reviewed breaking API changes
upgrade_acknowledgements_for = "4.17"

# 4. Apply the upgrade
terraform apply -var-file=prod.tfvars
```

> **Note**: For Classic clusters using STS, the RHCS provider automatically upgrades
> IAM policies if they're incompatible with the target version.

#### ROSA HCP Upgrades

HCP clusters have a **decoupled control plane and machine pools**. The upgrade order is:

1. **Upgrade control plane FIRST** (does not impact worker nodes)
2. **Then upgrade machine pools** (can upgrade multiple pools concurrently)

```bash
# 1. Check current versions
rosa describe cluster --cluster=<cluster-name>
rosa list machinepool --cluster=<cluster-name>

# 2. Update tfvars with target version
openshift_version = "4.17.0"

# 3. If upgrading to a new minor version (e.g., 4.16 → 4.17), add acknowledgement
# This confirms you've reviewed breaking API changes
upgrade_acknowledgements_for = "4.17"

# 4. Apply to upgrade control plane first
terraform apply -var-file=prod.tfvars

# 5. Then upgrade machine pools (if managed separately)
# Machine pools must stay within n-2 of control plane version
```

**HCP Version Constraints**:
- Machine pools cannot use a **newer** version than the control plane
- Machine pools must be within **2 minor versions** (n-2) of the control plane
- Example: Control plane 4.17.x supports machine pools 4.15.x, 4.16.x, 4.17.x

#### Upgrade Acknowledgements

When upgrading to certain versions, OpenShift requires acknowledgement of breaking
changes (removed APIs, deprecations). The RHCS provider surfaces this as:

```hcl
# Add to your cluster resource or tfvars when required
upgrade_acknowledgements_for = "4.17"  # Target minor version
```

If you don't add this and it's required, Terraform will error with a message
explaining what changes require acknowledgement.

#### Hybrid Management: Console + Terraform

You can upgrade clusters via the Hybrid Cloud Console (OCM UI) and then sync Terraform
state, or use automatic z-stream updates and later do y-stream upgrades via Terraform.

##### Scenario 1: Upgraded via Console, Sync to Terraform

If someone upgrades the cluster via the Hybrid Cloud Console instead of Terraform:

```bash
# 1. Check current cluster version (shows actual version from API)
rosa describe cluster --cluster=<cluster-name>

# 2. Review what Terraform sees as drift
terraform plan -refresh-only -var-file=prod.tfvars

# 3. The plan will show version difference, but due to lifecycle ignore_changes,
#    Terraform will NOT try to "downgrade" the cluster

# 4. Update your tfvars to match the actual version
openshift_version = "4.17.3"  # Match what's actually deployed

# 5. Apply to sync state (no changes to cluster)
terraform apply -var-file=prod.tfvars
```

The cluster modules include `lifecycle { ignore_changes = [version] }` which prevents
Terraform from attempting to change the cluster version when it detects drift. This
is intentional - upgrades should always be explicit, not automatic "corrections".

##### Scenario 2: Automatic Z-Stream Updates + Y-Stream via Terraform

If you enable automatic z-stream updates in the Console (e.g., weekly updates to latest
4.17.x), you can still do y-stream upgrades via Terraform:

```bash
# 1. Cluster has auto-upgraded: 4.17.0 → 4.17.1 → 4.17.3 (via Console)
rosa describe cluster --cluster=<cluster-name>
# Shows: OpenShift Version: 4.17.3

# 2. Your tfvars still has:
#    openshift_version = "4.17.0"

# 3. Refresh state to pick up current version
terraform apply -refresh-only -var-file=prod.tfvars
# State now knows cluster is at 4.17.3

# 4. For y-stream upgrade (4.17 → 4.18), update tfvars:
openshift_version = "4.18.0"
upgrade_acknowledgements_for = "4.18"

# 5. Apply the y-stream upgrade
terraform apply -var-file=prod.tfvars
```

##### Understanding lifecycle ignore_changes

Both Classic and HCP cluster modules use:

```hcl
lifecycle {
  ignore_changes = [version]
}
```

This means:
- **On plan**: Terraform sees the version difference but won't propose changes
- **On apply**: Terraform won't try to modify the cluster version
- **To upgrade**: You must explicitly change `openshift_version` in tfvars

This design supports hybrid management where:
- Operations teams can use Console for routine z-stream updates
- Platform teams can use Terraform for major y-stream upgrades
- State stays accurate via `terraform apply -refresh-only`

##### State Refresh Commands

```bash
# Preview what refresh would change (safe, read-only)
terraform plan -refresh-only -var-file=prod.tfvars

# Apply the refresh to sync state with actual infrastructure
terraform apply -refresh-only -var-file=prod.tfvars

# Full plan showing any drift including version (informational)
terraform plan -var-file=prod.tfvars
```

**Reference Documentation**:
- [ROSA HCP Upgrades](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/upgrading/rosa-hcp-upgrading)
- [ROSA Classic Upgrades](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/upgrading/rosa-upgrading-sts)
- [RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)
- [Terraform Refresh Mode](https://developer.hashicorp.com/terraform/tutorials/state/refresh)

---

## Client VPN Operations

### Create VPN On-Demand

```bash
# Budget 15-20 minutes
cd environments/<environment>
terraform apply -var-file=prod.tfvars -target=module.client_vpn
```

### Destroy VPN (Cost Savings)

```bash
# Budget 15-25 minutes
terraform destroy -var-file=prod.tfvars -target=module.client_vpn
```

### VPN Troubleshooting

```bash
# Check endpoint status
aws ec2 describe-client-vpn-endpoints \
  --query 'ClientVpnEndpoints[*].[ClientVpnEndpointId,Status.Code]' \
  --output table

# Check associations
aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id cvpn-endpoint-XXXX
```

### macOS DNS Issues

```bash
# List network interfaces
networksetup -listallnetworkservices

# Check current DNS settings
networksetup -getdnsservers Wi-Fi

# Set VPC DNS while connected to VPN
sudo networksetup -setdnsservers Wi-Fi 10.0.0.2

# Restore automatic DNS after VPN disconnect
sudo networksetup -setdnsservers Wi-Fi empty

# Flush DNS cache (if DNS is stale)
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

**Note:** Replace `Wi-Fi` with your interface name (e.g., `Ethernet`).

---

## Troubleshooting

### Token Expired

```
Error: invalid_grant: Invalid refresh token
```

**Fix:**

*Commercial:*
1. Verify service account at https://console.redhat.com/iam/service-accounts
2. If secret was lost, delete and recreate the service account
3. `export TF_VAR_rhcs_client_id="your-client-id"`
4. `export TF_VAR_rhcs_client_secret="your-client-secret"`
5. Retry

*GovCloud:*
1. Get new token from https://console.openshiftusgov.com/openshift/token
2. `export TF_VAR_ocm_token="new-token"`
3. `unset RHCS_TOKEN RHCS_URL`
4. Retry

### OIDC Delete Fails

```
Error: can't delete OIDC configuration
```

**Fix:** Wait for cluster deletion to complete:
```bash
rosa list clusters
# Wait until cluster is gone, then retry destroy
```

### Service-Linked Role Missing

```
Error: Service linked role for elasticloadbalancing not found
```

**Fix:**
```bash
aws iam create-service-linked-role \
  --aws-service-name elasticloadbalancing.amazonaws.com
```

### HTPasswd Login Fails After Create

**Fix:** Wait 2-5 minutes for OAuth operator to reconcile:
```bash
# From jump host
oc get clusteroperator authentication
oc get pods -n openshift-authentication -w
```

### GitOps Installation Fails

When `install_gitops = true` but GitOps/ArgoCD doesn't appear in the cluster.

**Check Authentication Status:**
```bash
# Check if cluster_auth obtained a token
terraform output cluster_auth_summary

# Expected output for success:
# {
#   "authenticated" = true
#   "enabled" = true
#   "error" = ""
#   "host" = "https://api.xxx.openshiftapps.com:6443"
#   "username" = "cluster-admin"
# }
```

**Common Failures:**

| Error | Cause | Fix |
|-------|-------|-----|
| `error: "oauth server not reachable"` | OAuth server not accessible | Connect via VPN or set `gitops_oauth_url` |
| `error: "HTTP 403"` | Wrong OAuth URL being used | Discover and set `gitops_oauth_url` (see below) |
| `error: "authentication failed"` | Invalid credentials | Check htpasswd IDP exists, verify password |
| `error: "invalid credentials"` | Wrong username/password | Verify with `oc login` manually |
| `error: "curl not found"` | curl not installed | Install curl on Terraform runner |

**OAuth Token Retry Behavior**

The OAuth token retrieval includes automatic retry logic to handle temporary unavailability during OAuth server restarts (e.g., after IDP configuration changes).

Default behavior:
- **6 retry attempts** with exponential backoff
- **10s initial wait**, doubling up to **30s max** between retries
- **~2 minute maximum** wait time before failing
- Permanent errors (401/403) fail immediately without retry

You can customize the retry behavior via environment variables:

```bash
# Set before running terraform apply
export OAUTH_MAX_RETRIES=10      # Default: 6
export OAUTH_INITIAL_WAIT=5      # Default: 10 seconds
export OAUTH_MAX_WAIT=60         # Default: 30 seconds
```

When retries occur, you'll see messages like:
```
OAuth token retrieval attempt 1 failed (oauth_not_reachable), retrying in 10s...
OAuth token retrieval attempt 2 failed (auth_failed), retrying in 20s...
```

**Step 1: Discover OAuth URL**

The OAuth server URL varies by OpenShift version and configuration:

```bash
# Log into the cluster first
oc login $(terraform output -raw cluster_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw cluster_admin_password)

# Discover OAuth route
oc get route -n openshift-authentication oauth-openshift -o jsonpath='{.spec.host}'
# Example output: oauth-openshift.apps.rosa-dev.veyx.p1.openshiftapps.com
```

**Standard OAuth URL patterns:**
| Version/Type | OAuth URL Pattern |
|--------------|-------------------|
| OCP 4.x / ROSA Classic | `https://oauth-openshift.apps.<cluster>.<domain>` |
| HCP with managed auth | `https://oauth-openshift.apps.<cluster>.<domain>` |
| HCP with external auth | Varies - use discovery command above |
| GovCloud (4.16+) | `https://oauth-openshift.apps.<cluster>.<domain>` |

**Step 2: Test OAuth Manually**

```bash
# Get credentials
PASSWORD=$(terraform output -raw cluster_admin_password)

# Discover OAuth URL
OAUTH_URL="https://$(oc get route -n openshift-authentication oauth-openshift -o jsonpath='{.spec.host}')"

# Create base64 auth header
AUTH=$(printf 'cluster-admin:%s' "$PASSWORD" | base64)

# Test OAuth flow
curl -sk -I \
  -H "Authorization: Basic $AUTH" \
  -H "X-CSRF-Token: 1" \
  "$OAUTH_URL/oauth/authorize?response_type=token&client_id=openshift-challenging-client"

# SUCCESS: HTTP/1.1 302 Found with Location header containing access_token=
# FAILURE: HTTP 401 (bad credentials) or HTTP 403 (wrong URL or access denied)
```

**Step 3: Set OAuth URL Override (if needed)**

If auto-discovery doesn't work, set the OAuth URL in your tfvars:

```hcl
# dev.tfvars
gitops_oauth_url = "https://oauth-openshift.apps.rosa-dev.veyx.p1.openshiftapps.com"
```

**Step 4: Alternative - Provide Your Own Token**

For HCP with external auth (OIDC, LDAP) or when htpasswd IDP is not available:

```bash
# Log in manually
oc login <cluster-api-url> -u <your-user>

# Get token
TOKEN=$(oc whoami -t)
echo $TOKEN
```

```hcl
# dev.tfvars - use pre-obtained token
gitops_cluster_token = "<your-token-here>"  # e.g., sha256~xxxxx...
```

**Step 5: Verify GitOps Installation**

```bash
# Check subscription
oc get subscription -n openshift-operators openshift-gitops-operator

# Check operator status
oc get csv -n openshift-operators | grep gitops

# Check ArgoCD instance
oc get argocd -n openshift-gitops

# Check ArgoCD route
oc get route -n openshift-gitops openshift-gitops-server
```

**Private Cluster GitOps:**

For private clusters, the Terraform runner must reach the OAuth server:

1. **Option A: Client VPN** - Connect before running terraform apply
2. **Option B: Jump Host** - Run terraform from the jump host
3. **Option C: Two-Phase** - Deploy cluster first, connect VPN, then enable GitOps

```bash
# Two-phase approach
# Phase 1: Deploy cluster without GitOps
install_gitops = false
terraform apply -var-file=dev.tfvars

# Phase 2: Connect VPN, discover OAuth URL, enable GitOps
install_gitops = true
gitops_oauth_url = "https://oauth-openshift.apps...."  # discovered value
terraform apply -var-file=dev.tfvars
```

### State Lock Issues

```bash
# Local state
rm -f .terraform.tfstate.lock.info

# S3 + DynamoDB backend
aws dynamodb delete-item \
  --table-name terraform-locks \
  --key '{"LockID": {"S": "your-state-path"}}'
```

### VPC Destroy Stuck

When `terraform destroy` hangs on VPC resources (routes, subnets, endpoints), there may be leftover resources blocking deletion - especially if the ROSA cluster was deleted outside of Terraform (e.g., via the Hybrid Cloud Console).

**Diagnose:**
```bash
# Get your VPC ID
VPC_ID=$(terraform state show module.vpc.aws_vpc.this 2>/dev/null | grep '"id"' | awk -F'"' '{print $4}')
echo "VPC ID: $VPC_ID"

# Check for leftover ENIs
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,Description:Description}'

# Check NAT Gateways (common blocker)
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[*].{ID:NatGatewayId,State:State}'

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].{ID:GroupId,Name:GroupName}'
```

**Fix:**
```bash
# Delete NAT Gateway if stuck
aws ec2 delete-nat-gateway --nat-gateway-id nat-XXXXX

# Wait for deletion (~1 min)
aws ec2 describe-nat-gateways --nat-gateway-ids nat-XXXXX --query 'NatGateways[0].State'

# Delete orphan ENIs (after detaching if needed)
aws ec2 delete-network-interface --network-interface-id eni-XXXXX

# Then re-run terraform destroy
```

---

## Platform Differences: Classic vs HCP

ROSA Classic and ROSA HCP have architectural differences that affect authentication, networking, and cluster management.

### OAuth and Authentication

| Aspect | Classic | HCP |
|--------|---------|-----|
| OAuth Server Location | Runs in customer cluster | Runs in Red Hat's hosted control plane |
| OAuth Route | `openshift-authentication` namespace | No route in customer cluster |
| OAuth URL Pattern | `https://oauth-openshift.apps.<cluster>.<domain>` | `https://oauth.<cluster>.<domain>:443` |
| API Port | `:6443` | `:443` |

**Discovering OAuth URL:**

The OAuth URL can be auto-discovered from the API server's `.well-known` endpoint:

```bash
# Works for both Classic and HCP
curl -sk https://<api-url>/.well-known/oauth-authorization-server | jq .issuer
```

Example responses:
```bash
# Classic
"https://oauth-openshift.apps.my-cluster.abcd.p1.openshiftapps.com"

# HCP
"https://oauth.my-cluster.abcd.p3.openshiftapps.com:443"
```

### Control Plane Components

| Component | Classic | HCP |
|-----------|---------|-----|
| etcd | Runs in customer VPC | Red Hat managed |
| API Server | Runs in customer VPC | Red Hat managed, accessed via PrivateLink |
| Controllers | Runs in customer VPC | Red Hat managed |
| OAuth Server | Runs in customer VPC | Red Hat managed |
| Worker Nodes | Customer VPC | Customer VPC |

### IAM Roles

| Role Type | Classic | HCP |
|-----------|---------|-----|
| Account Roles | 4 (cluster-scoped) | 3 (account-level, shared) |
| Operator Roles | 6-7 per cluster | 8 per cluster |
| Role Lifecycle | Destroyed with cluster | Persist independently |

See [IAM Lifecycle Management](IAM-LIFECYCLE.md) for details.

### Networking

| Aspect | Classic | HCP |
|--------|---------|-----|
| Control Plane Access | Direct (in VPC) | AWS PrivateLink |
| Default Ingress | `*.apps.<cluster>.<domain>` | `*.apps.rosa.<cluster>.<domain>` |
| Private Cluster | Optional | Optional (required for GovCloud) |

### Debugging Authentication Issues

**Check OAuth discovery:**
```bash
# Get actual OAuth endpoints
curl -sk https://<api-url>/.well-known/oauth-authorization-server | jq .
```

**Classic - Check OAuth route:**
```bash
oc get route -n openshift-authentication oauth-openshift
```

**HCP - No OAuth route exists** (it's hosted by Red Hat). Use the `.well-known` endpoint instead.

**Test OAuth connectivity:**
```bash
OAUTH_URL=$(curl -sk https://<api-url>/.well-known/oauth-authorization-server | jq -r .issuer)
curl -sk "${OAUTH_URL}/healthz"
```

---

## Known Issues

| Issue | Description | Workaround |
|-------|-------------|------------|
| VPN slow | Create/destroy takes 15-25 min | AWS limitation, use SSM for quick access |
| Token expiry | Operations fail after ~30 days | Refresh token from console |
| HCP version drift | Machine pools must be n-2 of CP | Upgrade control plane first, then pools |
| OAuth reconcile | Login fails immediately after IDP create | Wait 2-5 minutes |
| GovCloud quotas | VPC limit is 5 by default | Request increase via AWS Support |
| **Private + GitOps** | **GitOps fails on first apply** | **Two-phase deployment required - see above** |
| GitOps private cluster | GitOps install requires OAuth access | Connect to VPN before `terraform apply` |
| GitOps HTTP 403 | OAuth URL auto-derivation failed | Set `gitops_oauth_url` explicitly |
| GitOps HCP external auth | htpasswd IDP not available | Set `gitops_cluster_token` with manual token |
| VPC destroy stuck | NAT/ENI blocking VPC deletion | Delete NAT gateway manually, see troubleshooting |

---

## Additional Resources

- [Main README](../README.md) - Quick start and overview
- [Machine Pools Guide](MACHINE-POOLS.md) - GPU, bare metal, ARM/Graviton, spot instances
- [Client VPN Module](../modules/networking/client-vpn/README.md) - VPN details and pricing
- [GitOps Layers Guide](GITOPS-LAYERS-GUIDE.md) - Day 2 operations
- [IAM Lifecycle](IAM-LIFECYCLE.md) - Account vs cluster roles
- [ROSA Documentation](https://docs.openshift.com/rosa/welcome/index.html)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3) - Remote state setup
