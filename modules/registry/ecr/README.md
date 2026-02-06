# ECR Module

Creates an Amazon Elastic Container Registry (ECR) repository for ROSA clusters with VPC endpoints for private access.

## Use Cases

1. **Private Container Registry** - Store custom application images for any ROSA cluster (Classic or HCP)
2. **Operator Mirroring** - Mirror Red Hat operators for zero-egress HCP clusters

## Features

- **VPC Endpoints included by default** - Private ECR access without NAT charges
- Optional KMS encryption (defaults to AWS-managed AES-256)
- Image vulnerability scanning on push
- Lifecycle policies for automatic image cleanup
- Works with both Commercial and GovCloud regions
- Optional lifecycle protection (survives cluster destroy)

## VPC Endpoints (Enabled by Default)

This module creates VPC endpoints for ECR automatically when `create_vpc_endpoints = true` (default).

### Why VPC Endpoints Are On by Default

| Reason | Benefit |
|--------|---------|
| **Cost efficiency** | Image pulls go through VPC endpoint instead of NAT Gateway, avoiding NAT data processing charges (~$0.045/GB) |
| **Zero-egress support** | Required for air-gapped/private clusters that have no internet access |
| **Security** | All ECR traffic stays within AWS private network, never traverses the internet |
| **Performance** | Lower latency for image pulls within the same region |

### Endpoints Created

| Endpoint | Service | Purpose |
|----------|---------|---------|
| `ecr.api` | `com.amazonaws.<region>.ecr.api` | ECR API calls (CreateRepository, ListImages, etc.) |
| `ecr.dkr` | `com.amazonaws.<region>.ecr.dkr` | Docker registry operations (push/pull images) |

**Note:** The S3 gateway endpoint (required for ECR image layers) is created by the VPC module, not this module.

### Disabling VPC Endpoints

If you're using a shared VPC with existing ECR endpoints, or want to manage endpoints separately:

```hcl
# In tfvars - disable ECR endpoints
create_ecr             = true
create_vpc_endpoints = false  # Use existing endpoints
```

## Quick Start

Enable ECR in your environment's tfvars:

```hcl
# dev.tfvars or prod.tfvars
create_ecr = true

# Optional: Custom repository name (defaults to {cluster_name}-registry)
# ecr_repository_name = "my-custom-registry"

# Optional: Preserve ECR when cluster is destroyed
# ecr_prevent_destroy = true
```

## What Happens When ECR is Enabled

When `create_ecr = true`:

1. **ECR Repository Created** - A private container registry in your AWS account
2. **IAM Policy Attached** - `AmazonEC2ContainerRegistryReadOnly` is attached to worker node IAM roles
3. **Worker Nodes Can Pull** - All pods in the cluster can pull images from this ECR without additional configuration

No manual OpenShift configuration is needed for basic image pulls.

### How ECR Policy Attachment Works (HCP vs Classic)

The ECR policy attachment differs between HCP and Classic due to their IAM architectures:

| Platform | How ECR Policy is Attached | Scope |
|----------|---------------------------|-------|
| **HCP** | Per-machine-pool via `instance_profile` | Each pool can have independent ECR access |
| **Classic** | Account-level Worker role | All workers in clusters using same role prefix |

**For HCP clusters:**
- Each machine pool gets its own `instance_profile` (computed by ROSA)
- The environment passes `attach_ecr_policy = var.create_ecr` to enable ECR
- Additional machine pools can set `attach_ecr_policy = true` individually

**For Classic clusters:**
- The account-level Worker role is shared across clusters
- ECR policy is attached when `attach_ecr_policy = true` on the cluster module

### Why Pull Only? (No Push by Default)

This module intentionally provides **read-only (pull)** access to workers, not push. Here's why:

| Approach | Security | Scope |
|----------|----------|-------|
| **Pull on workers (current)** | ✅ Safe | All pods can pull - low risk, images are already published |
| **Push on workers** | ❌ Risky | All pods could overwrite images - supply chain attack vector |
| **Push via IRSA** | ✅ Safe | Only designated build pipelines can push |

**Security rationale:**
- Granting push permissions to all worker nodes means any compromised pod could overwrite your container images
- This is a supply chain security risk - attackers could inject malicious code into trusted images
- The principle of least privilege dictates that only build pipelines should have push access

**The right approach for push:**
- Use IRSA (IAM Roles for Service Accounts) to grant push to specific ServiceAccounts
- This limits push capability to explicitly designated build pipelines
- See [CI/CD Pipeline Push Support](#cicd-pipeline-push-support) below

**Pull and push paths are independent:**
- Pull: Worker IAM role (instance profile) → ReadOnly policy
- Push: ServiceAccount annotation → IRSA → Separate push role

Adding IRSA push won't affect pull - they use different authentication mechanisms.

## Pushing Images from Your Workstation

### Prerequisites

- AWS CLI configured with credentials for the target account
- Docker (or Podman) installed
- Permissions to push to ECR (`ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, etc.)

### Step-by-Step

```bash
# 1. Get the ECR repository URL from Terraform
cd environments/<your-environment>
REPO_URL=$(terraform output -raw ecr_repository_url)
REGISTRY_URL=$(terraform output -raw ecr_registry_url)

# 2. Authenticate Docker to ECR
# For Commercial AWS:
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${REGISTRY_URL}

# For GovCloud:
aws ecr get-login-password --region us-gov-west-1 | \
  docker login --username AWS --password-stdin ${REGISTRY_URL}

# 3. Tag your local image with the ECR repository URL
docker tag my-app:v1.0 ${REPO_URL}:v1.0
docker tag my-app:v1.0 ${REPO_URL}:latest

# 4. Push to ECR
docker push ${REPO_URL}:v1.0
docker push ${REPO_URL}:latest

# 5. Verify the push
aws ecr list-images --repository-name $(terraform output -raw ecr_repository_name)
```

### Using Podman Instead of Docker

```bash
# Authenticate (same command works with podman)
aws ecr get-login-password --region us-gov-west-1 | \
  podman login --username AWS --password-stdin ${REGISTRY_URL}

# Tag and push
podman tag my-app:v1.0 ${REPO_URL}:v1.0
podman push ${REPO_URL}:v1.0
```

## Using ECR Images in Kubernetes/OpenShift

Once images are pushed, use them in your deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        # Use the full ECR repository URL
        image: 123456789012.dkr.ecr.us-gov-west-1.amazonaws.com/my-cluster-registry:v1.0
        ports:
        - containerPort: 8080
```

**Note:** No `imagePullSecrets` needed - worker nodes already have IAM permissions to pull from ECR.

## ECR Lifecycle Protection

To preserve your ECR repository when destroying the cluster:

```hcl
# In tfvars
create_ecr          = true
ecr_prevent_destroy = true
```

When `ecr_prevent_destroy = true`:
- Repository survives `terraform destroy` of the cluster
- Useful for shared registries or preserving images across cluster rebuilds
- Tagged with `Lifecycle = "external"` for visibility

**To destroy a protected ECR:**
```bash
# 1. Update tfvars
ecr_prevent_destroy = false

# 2. Targeted destroy
terraform destroy -target=module.ecr
```

## CI/CD Pipeline Push Support

By default, worker nodes only have **read** access to ECR. To allow builds running on ROSA (e.g., OpenShift Pipelines/Tekton, Jenkins, GitHub Actions runners) to **push** images, you need to set up IAM Roles for Service Accounts (IRSA).

### High-Level Steps

1. **Create an IAM Role** with ECR push permissions (`ecr:PutImage`, `ecr:InitiateLayerUpload`, etc.)
2. **Configure OIDC Trust** - Allow the ROSA cluster's OIDC provider to assume the role
3. **Annotate ServiceAccount** - Add the IAM role ARN annotation to your build pipeline's ServiceAccount
4. **Use the ServiceAccount** - Configure your build pods to use this ServiceAccount

### Example IAM Policy for Push

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:<region>:<account>:repository/<repo-name>"
    }
  ]
}
```

### ServiceAccount Annotation

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline-builder
  namespace: my-pipeline
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ECRPushRole
```

### Official Documentation

- [ROSA: Using IAM Roles for Service Accounts (IRSA)](https://docs.openshift.com/rosa/cloud_experts_tutorials/cloud-experts-using-sts.html)
- [AWS: Private registry authentication (ECR)](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [OpenShift Pipelines with ECR](https://docs.openshift.com/pipelines/latest/create/using-tekton-hub-with-pipelines.html)
- [AWS: ECR IAM Policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security-iam.html)

### Alternative: Use `oc` Credentials Helper

For simpler setups, you can create a Secret with ECR credentials:

```bash
# Get ECR token (expires in 12 hours)
TOKEN=$(aws ecr get-login-password --region us-gov-west-1)

# Create pull/push secret
oc create secret docker-registry ecr-push-secret \
  --docker-server=<account>.dkr.ecr.<region>.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${TOKEN}" \
  -n my-pipeline

# Link to ServiceAccount
oc secrets link pipeline -n my-pipeline ecr-push-secret
```

**Note:** This approach requires refreshing the secret every 12 hours. IRSA is preferred for production.

## For Zero-Egress Clusters

See [docs/ZERO-EGRESS.md](../../../docs/ZERO-EGRESS.md) for:
- Operator mirroring workflow using `oc mirror`
- ImageDigestMirrorSet configuration
- Complete air-gapped setup instructions

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the ROSA cluster | `string` | - | yes |
| repository_name | Custom repository name (defaults to {cluster_name}-registry) | `string` | `""` | no |
| kms_key_arn | KMS key ARN for encryption | `string` | `null` | no |
| prevent_destroy | Protect ECR from cluster destruction | `bool` | `false` | no |
| image_tag_mutability | MUTABLE or IMMUTABLE | `string` | `"MUTABLE"` | no |
| scan_on_push | Enable vulnerability scanning | `bool` | `true` | no |
| lifecycle_policy_enabled | Enable image retention policy | `bool` | `true` | no |
| lifecycle_untagged_days | Days to keep untagged images | `number` | `14` | no |
| lifecycle_keep_count | Number of tagged images to retain | `number` | `30` | no |
| force_delete | Force delete even if images exist | `bool` | `false` | no |
| generate_idms | Generate IDMS config for zero-egress | `bool` | `false` | no |
| tags | Tags for resources | `map(string)` | `{}` | no |

### VPC Endpoint Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create_vpc_endpoints | Create VPC endpoints for ECR | `bool` | `true` | no |
| vpc_id | VPC ID for endpoints | `string` | `null` | yes (if endpoints enabled) |
| private_subnet_ids | Subnet IDs for endpoint ENIs | `list(string)` | `[]` | yes (if endpoints enabled) |
| endpoint_security_group_ids | Custom security groups for endpoints | `list(string)` | `[]` | no |
| vpc_cidr | VPC CIDR for default security group | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| repository_url | Full URL for docker push/pull |
| repository_arn | ARN of the repository |
| repository_name | Name of the repository |
| registry_id | AWS account ID (registry ID) |
| registry_url | ECR registry URL for docker login |
| prevent_destroy | Whether lifecycle protection is enabled |
| ecr_summary | Summary of ECR configuration |
| idms_config_path | Path to IDMS config file (if generated) |
| idms_config_content | IDMS YAML content (if generated) |
| ecr_api_endpoint_id | ID of the ECR API VPC endpoint |
| ecr_dkr_endpoint_id | ID of the ECR DKR VPC endpoint |
| endpoint_security_group_id | Security group ID for endpoints (if created) |
| vpc_endpoints_enabled | Whether VPC endpoints were created |

## Troubleshooting

### "no basic auth credentials" when pushing

Re-authenticate to ECR - tokens expire after 12 hours:
```bash
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <registry-url>
```

### "denied: User ... cannot perform ecr:GetAuthorizationToken"

Your AWS credentials don't have ECR permissions. Ensure your IAM user/role has:
- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:GetDownloadUrlForLayer`
- `ecr:BatchGetImage`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`

Or attach the `AmazonEC2ContainerRegistryPowerUser` managed policy.

### Pods can't pull images (ImagePullBackOff)

1. Verify the image exists: `aws ecr list-images --repository-name <repo-name>`
2. Check the image URL in your deployment matches exactly
3. Verify ECR is enabled: `terraform output cluster_summary | grep ecr`
4. Check IAM policy attachment:
   - **Classic**: `aws iam list-attached-role-policies --role-name <prefix>-Worker-Role`
   - **HCP**: `aws iam get-instance-profile --instance-profile-name <pool-instance-profile>`
