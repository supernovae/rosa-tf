# Zero-Egress ROSA HCP Clusters

This guide covers deploying and operating ROSA HCP clusters in zero-egress (air-gapped) mode, where clusters have no outbound internet connectivity.

## Overview

Zero-egress ROSA HCP clusters are designed for environments with strict network isolation requirements:

- **No NAT Gateway** - No internet gateway or NAT gateway required
- **No Outbound Internet** - Cluster nodes cannot reach the internet
- **Regional ECR** - OpenShift images pulled from Red Hat's regional ECR mirror
- **Custom Operators** - Operators must be mirrored to your private ECR

```
┌───────────────────────────────────────────────────────────────┐
│                          AWS Region                           │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                  Your VPC (no IGW/NAT)                  │  │
│  │  ┌──────────────┐      ┌───────────────────────────┐    │  │
│  │  │  ROSA HCP    │◄────►│  Your ECR (Operators)     │    │  │
│  │  │  Workers     │      └───────────────────────────┘    │  │
│  │  └──────┬───────┘                                       │  │
│  │         │                                               │  │
│  │         ▼                                               │  │
│  │  ┌──────────────────────────────────────────────┐       │  │
│  │  │  Red Hat Regional ECR (OpenShift images)     │       │  │
│  │  │  (Managed by Red Hat via PrivateLink)        │       │  │
│  │  └──────────────────────────────────────────────┘       │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌──────────────────────┐                                     │
│  │  Red Hat SRE         │◄── PrivateLink (private clusters)   │
│  │  (Control Plane)     │                                     │
│  └──────────────────────┘                                     │
└───────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **ROSA HCP Only** - Zero-egress is only available for HCP clusters (not Classic)
2. **Private Cluster** - Must be deployed as a private cluster (`private_cluster = true`)
3. **VPN or Jump Host** - Network access for cluster management
4. **oc-mirror CLI** - For mirroring operators to ECR
5. **Pull Secret** - From [console.redhat.com](https://console.redhat.com/openshift/downloads)

## Enabling Zero-Egress

### Quick Start with Example

Use the provided example tfvars for a complete zero-egress configuration:

```bash
cp examples/zeroegress.tfvars environments/commercial-hcp/my-cluster.tfvars
# Edit cluster_name, aws_region, etc.
terraform apply -var-file="my-cluster.tfvars"
```

### Terraform Configuration

```hcl
# environments/commercial-hcp/dev.tfvars or environments/govcloud-hcp/dev.tfvars

# Enable zero-egress mode
zero_egress     = true
private_cluster = true  # Required when zero_egress = true

# Create ECR for operator mirroring
create_ecr = true
# ecr_repository_name = "custom-name"  # Optional

# VPN for cluster access (essential for zero egress)
create_client_vpn = true
ssm_enabled       = true  # Backup access for node debugging

# GitOps disabled until operators are mirrored
install_gitops = false
```

### What Terraform Creates

When `zero_egress = true`:

1. **VPC without internet** - No IGW, NAT gateway, or public subnets
2. **ECR Repository** - Private registry for mirrored operators (if `create_ecr = true`)
3. **IAM Policies** - Worker nodes get `AmazonEC2ContainerRegistryReadOnly` policy
4. **Zero-egress cluster property** - Enables Red Hat's regional ECR for OpenShift images

## Operator Mirroring Workflow

Since zero-egress clusters cannot reach the internet, operators from the OperatorHub must be mirrored to your private ECR.

### Workflow Diagram

```
┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐
│  Internet-Connected│     │   Air Gap          │     │  Zero-Egress       │
│  Workstation       │────►│   (USB/S3)         │────►│  Network           │
│                    │     │                    │     │                    │
│  1. oc-mirror      │     │  2. Transfer       │     │  3. Push to ECR    │
│     download       │     │     mirror-data    │     │     4. Apply IDMS  │
└────────────────────┘     └────────────────────┘     └────────────────────┘
```

### Step 1: Generate Mirror Configuration

Use the provided helper script to generate an `ImageSetConfiguration`:

```bash
# Generate config for all GitOps layer operators (RECOMMENDED)
./scripts/mirror-operators.sh layers --ocp-version 4.18

# Generate config with ECR URL for complete instructions
./scripts/mirror-operators.sh layers \
  --ocp-version 4.18 \
  --ecr-url $(terraform output -raw ecr_registry_url)

# Or use minimal for just GitOps + Web Terminal
./scripts/mirror-operators.sh minimal --ocp-version 4.18
```

**Profiles:**

| Profile | Operators | Approx Size |
|---------|-----------|-------------|
| **layers** | GitOps, Terminal, Virtualization, COO, Loki, Logging, OADP | ~25GB |
| minimal | GitOps, Web Terminal | ~5GB |
| standard | GitOps, Terminal, OADP, Logging, Cert Manager | ~15GB |
| full | All certified operators | ~100GB+ |
| custom | Your selection | Varies |

**Note:** `oc-mirror` automatically resolves operator dependencies. If an operator
requires another operator, it will be included automatically.

### Step 2: Mirror Operators (Internet-Connected Side)

```bash
# Authenticate to Red Hat registry
oc-mirror login registry.redhat.io

# Mirror to local disk
oc-mirror --config ./mirror-workspace/imageset-config-standard.yaml \
  file://./mirror-data
```

### Step 3: Transfer to Air-Gapped Network

Transfer the `mirror-data` directory to the air-gapped network:

- **USB Drive** - For physical air gap
- **S3 Bucket** - Using `aws s3 sync` if cross-region connectivity exists
- **Secure File Transfer** - As per your organization's policy

### Step 4: Push to ECR (Air-Gapped Side)

```bash
# Get ECR URL from Terraform
ECR_URL=$(terraform output -raw ecr_registry_url)

# Authenticate to ECR
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin $ECR_URL

# Push mirrored content to ECR
oc-mirror --from ./mirror-data docker://$ECR_URL
```

### Step 5: Apply IDMS (ImageDigestMirrorSet)

The mirror script generates an IDMS configuration that tells the cluster to pull images from your ECR instead of the internet:

```bash
# Get cluster admin credentials
USERNAME=$(terraform output -raw cluster_admin_username)
PASSWORD=$(terraform output -raw cluster_admin_password)
API_URL=$(terraform output -raw cluster_api_url)

# Connect via VPN or jump host, then login
oc login $API_URL -u $USERNAME -p $PASSWORD

# Apply IDMS
oc apply -f ./mirror-workspace/idms-config.yaml
```

**Sample IDMS:**

```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: rosa-operator-mirror
spec:
  imageDigestMirrors:
    - source: registry.redhat.io/redhat
      mirrors:
        - <account>.dkr.ecr.<region>.amazonaws.com/redhat
    - source: quay.io/openshift-release-dev
      mirrors:
        - <account>.dkr.ecr.<region>.amazonaws.com/openshift-release-dev
```

### Step 6: Enable GitOps

After IDMS is applied, you can enable GitOps:

```hcl
# Update tfvars
install_gitops        = true
enable_layer_terminal = true
enable_layer_oadp     = true
```

```bash
terraform apply -var-file=dev.tfvars
```

## Cluster Access

If your VPC isn't connected via Direct Connect, Corporate VPN or gateways then Zero-egress clusters require VPN or jump host for access since there's no public endpoint.

### Option 1: SSM Jump Host

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw jumphost_instance_id)

# Connect via SSM
aws ssm start-session --target $INSTANCE_ID --region <region>

# From jump host, login to cluster
oc login https://api.<cluster>.<domain>:6443 -u cluster-admin
```

### Option 2: Client VPN

```bash
# Download VPN config (generated by Terraform)
# Import into OpenVPN client and connect

# Then access cluster directly from your workstation
oc login $(terraform output -raw cluster_api_url) -u cluster-admin
```

## Upgrading Zero-Egress Clusters

When upgrading a zero-egress cluster:

1. **Mirror new version first** - Update `ImageSetConfiguration` with new version range
2. **Push to ECR** - Follow the mirror workflow
3. **Verify IDMS** - Ensure IDMS covers the new release images
4. **Upgrade control plane** - Via Terraform or OCM Console
5. **Upgrade machine pools** - Within n-2 of control plane

```bash
# Update imageset config for new version
./scripts/mirror-operators.sh layers --ocp-version 4.18

# Mirror and push
oc-mirror --config ./mirror-workspace/imageset-config-layers.yaml file://./mirror-data
oc-mirror --from ./mirror-data docker://$ECR_URL

# Update Terraform
# openshift_version = "4.18.x"
terraform apply -var-file=dev.tfvars
```

## Troubleshooting

### Image Pull Failures

```bash
# Check IDMS is applied
oc get imagedigestmirrorset

# Verify mirror sources
oc get imagedigestmirrorset rosa-operator-mirror -o yaml

# Check machine config pool status (IDMS requires node restart)
oc get mcp
```

### ECR Authentication Issues

```bash
# Verify worker nodes have ECR access
oc debug node/<node-name> -- chroot /host aws ecr get-login-password

# Check ECR policy on worker role
# Classic: Policy attached to account Worker role
aws iam list-attached-role-policies --role-name <prefix>-Worker-Role

# HCP: Policy attached to per-pool instance profile
# Get instance profile from terraform output
terraform output -json machine_pools | jq '.[].instance_profile'
aws iam get-instance-profile --instance-profile-name <instance-profile-name>
```

### Operator Installation Failures

```bash
# Check catalog source
oc get catalogsource -n openshift-marketplace

# Verify images are mirrored
aws ecr describe-images --repository-name redhat/redhat-operator-index

# Check operator subscription status
oc get subscription -A
oc describe subscription <name> -n <namespace>
```

## Cost Considerations

Zero-egress deployments have different cost characteristics:

| Component | Zero-Egress | Standard |
|-----------|-------------|----------|
| NAT Gateway | $0/month | ~$32-96/month |
| Data Transfer (NAT) | $0 | ~$45/TB |
| ECR Storage | ~$2-10/month | $0 |
| ECR Data Transfer | Varies | $0 |

**Net effect**: Zero-egress can be cost-neutral or cost-saving depending on egress traffic patterns.

## Limitations

1. **HCP Only** - Zero-egress is not available for ROSA Classic
2. **No Internet Access** - Workloads cannot reach the internet without additional configuration
3. **Mirror Maintenance** - Operators must be re-mirrored before cluster upgrades
4. **GitOps Considerations** - Default "direct" installation method works; "applicationset" requires mirrored Git access or internal Git server

## Related Documentation

- [ROSA Zero-Egress Documentation](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html)
- [oc-mirror Documentation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-disconnected.html)
- [OPERATIONS.md](./OPERATIONS.md) - General cluster operations
- [ECR Module](../modules/registry/ecr/README.md) - ECR repository configuration
