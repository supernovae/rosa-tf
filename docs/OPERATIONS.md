# Operations Guide

Day-to-day operations, troubleshooting, and best practices for ROSA clusters.

## Table of Contents

- [Terraform State Management](#terraform-state-management)
- [Deployment Workflow](#deployment-workflow)
- [Credential Management](#credential-management)
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

### Deploy a Cluster

```bash
# 1. Navigate to environment
cd environments/<environment>

# 2. Set credentials
export TF_VAR_ocm_token="your-token"
export AWS_REGION="us-east-1"  # or us-gov-west-1 for GovCloud

# 3. Initialize and deploy
terraform init
terraform plan -var-file=dev.tfvars    # or prod.tfvars
terraform apply -var-file=dev.tfvars
```

### Two-Phase Deployment for Private Clusters

**⚠️ IMPORTANT: Private clusters (including all GovCloud clusters) require a two-phase deployment if you want to use GitOps layers.**

The Terraform runner must have network connectivity to the cluster API to install GitOps. For private clusters, this means you must:

1. **Phase 1**: Deploy the cluster and VPN infrastructure (without GitOps)
2. **Connect to VPN**: Download VPN config and connect
3. **Phase 2**: Enable GitOps and re-apply

```bash
# Phase 1: Deploy cluster + VPN (GitOps disabled)
# dev.tfvars:
#   install_gitops    = false
#   create_client_vpn = true

terraform apply -var-file=dev.tfvars
# Wait 45-60 min for cluster, 15-20 min for VPN

# Download VPN config
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > vpn-config.ovpn

# Connect to VPN (must be connected before Phase 2)
sudo openvpn --config vpn-config.ovpn

# Phase 2: Enable GitOps (while connected to VPN)
# Update dev.tfvars:
#   install_gitops = true

terraform apply -var-file=dev.tfvars
```

**Why Two Phases?**

| What Happens | Without VPN Connected |
|--------------|----------------------|
| Cluster creation | ✅ Works (uses AWS/ROSA APIs) |
| VPN creation | ✅ Works (AWS APIs only) |
| GitOps installation | ❌ Fails (can't reach cluster OAuth) |

GitOps requires authenticating to the cluster's OAuth server, which is only reachable from within the VPC for private clusters. Even if `create_client_vpn = true`, the VPN infrastructure exists but **you must actually connect to it** before GitOps can be installed.

**GovCloud Note:** All GovCloud clusters are private by design (FedRAMP requirement). The two-phase approach is **mandatory** for GovCloud + GitOps.

### Using Make Shortcuts

```bash
# Quick deployment
make commercial-classic-dev
make govcloud-hcp-prod

# Or with explicit variables
make plan ENV=commercial-hcp TFVARS=prod.tfvars
make apply ENV=govcloud-classic TFVARS=dev.tfvars
```

### Destroy a Cluster (Complete Guide)

Follow this guide to completely destroy a cluster and clean up all resources.

#### Step 1: Navigate to Your Environment

```bash
cd environments/<environment>  # e.g., commercial-hcp, govcloud-classic
```

#### Step 2: Run Destroy

```bash
# Standard destroy - disables GitOps to avoid cluster connectivity issues
terraform destroy \
  -var-file="dev.tfvars" \
  -var="install_gitops=false" \
  -var="enable_layer_monitoring=false" \
  -var="enable_layer_oadp=false" \
  -var="enable_layer_terminal=false" \
  -var="enable_layer_virtualization=false"
```

> **Why disable GitOps?** GitOps resources live inside the cluster and are automatically 
> destroyed when the cluster is deleted. Disabling GitOps skips cluster API authentication, 
> which avoids connectivity issues (especially for private clusters or when VPN is down).

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
| `Token is empty` | GitOps trying to auth | Add `-var="install_gitops=false"` |
| `connection refused` | Cluster API unreachable | Add `-var="install_gitops=false"` |
| VPC deletion fails | Resources still attached | Wait 5 min, retry; check for orphaned ENIs |

#### Quick One-Liner

```bash
terraform destroy -var-file="dev.tfvars" -var="install_gitops=false" \
  -var="enable_layer_monitoring=false" -var="enable_layer_oadp=false" \
  -var="enable_layer_terminal=false" -var="enable_layer_virtualization=false"
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

### OCM Tokens

| Environment | Token URL | API Endpoint |
|-------------|-----------|--------------|
| Commercial | console.redhat.com/openshift/token | api.openshift.com |
| GovCloud | console.openshiftusgov.com/openshift/token | api.openshiftusgov.com |

```bash
# Set token
export TF_VAR_ocm_token="your-offline-token"

# Clear conflicting variables
unset RHCS_TOKEN RHCS_URL

# Verify connectivity
rosa login --token="$TF_VAR_ocm_token"
rosa whoami
```

**Token Expiration:**
- Offline tokens expire after 30 days of inactivity
- Access tokens auto-refresh (~15 min lifetime)
- Enterprise IDP can configure custom lifetimes

**Switching Between Commercial and GovCloud:**

When switching between environments (e.g., Commercial to GovCloud or vice versa), always log out first to ensure a clean session:

```bash
# Log out of current environment
rosa logout

# Set new token for target environment
export TF_VAR_ocm_token="your-govcloud-or-commercial-token"

# Clear any cached environment variables
unset RHCS_TOKEN RHCS_URL

# Log in to new environment
rosa login --token="$TF_VAR_ocm_token"

# Verify you're connected to the correct environment
rosa whoami
```

> **Important:** The `rosa` CLI caches session state. Failing to log out before switching environments can cause connectivity issues or operations against the wrong Hybrid Cloud Console.

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
# Edit tfvars
install_gitops = true
enable_layer_terminal = true
enable_layer_oadp = true

# Apply (requires cluster access)
terraform apply -var-file=prod.tfvars
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
1. Get new token from console
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
