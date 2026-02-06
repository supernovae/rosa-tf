# OIDC Configuration Guide

This guide covers OIDC configuration options for ROSA clusters, including operator
role authentication (STS) and external authentication for users (HCP only).

## Overview

ROSA uses two distinct OIDC-related features:

1. **OIDC Config for STS** - Enables OpenShift operators to assume AWS IAM roles
   via Security Token Service (STS). Required for all ROSA clusters.

2. **External Authentication** (HCP only) - Replaces the built-in OpenShift OAuth
   server with direct integration to external OIDC identity providers (e.g., Entra ID).

## OIDC Configuration Modes (STS)

Three modes are supported for OIDC configuration:

| Mode | Hosted By | Key Management | Shareable | Use Case |
|------|-----------|----------------|-----------|----------|
| **Managed (per-cluster)** | Red Hat | Red Hat | No | Default, simplest |
| **Managed (registered)** | Red Hat | Red Hat | Yes | Faster deploys, shared across clusters |
| **Unmanaged** | Customer AWS | Customer (Secrets Manager) | Yes | Full control, compliance requirements |

### Mode 1: Managed OIDC (Default)

The simplest configuration. Red Hat hosts the OIDC provider and manages the
private key. A new OIDC configuration is created for each cluster.

```hcl
# tfvars
create_oidc_config = true
managed_oidc       = true
```

**Pros:**
- Zero configuration required
- Red Hat manages key rotation
- Fully supported

**Cons:**
- Each cluster has its own OIDC config
- Slightly longer cluster creation time

### Mode 2: Pre-created Managed OIDC

Use an existing OIDC configuration that was created beforehand. Useful for:
- Faster cluster deployments (IAM roles can be pre-created)
- Sharing OIDC across multiple development/test clusters

```hcl
# tfvars
create_oidc_config = false
oidc_config_id     = "abc123def456..."
oidc_endpoint_url  = "rh-oidc.s3.us-east-1.amazonaws.com/abc123..."
```

To obtain the OIDC config ID:
```bash
# Create registered OIDC config
rosa create oidc-config --managed --mode=auto

# List existing configs
rosa list oidc-config
```

**Warning:** Red Hat does not recommend sharing OIDC configurations in production
environments. Authentication verification applies across all clusters using the
shared configuration.

### Mode 3: Unmanaged OIDC (Customer-Managed)

Host the OIDC provider in your own AWS account with full control over the
private key.

```hcl
# tfvars
create_oidc_config          = true
managed_oidc                = false
oidc_private_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:oidc-key"
installer_role_arn_for_oidc = "arn:aws:iam::123456789:role/Installer-Role"
```

**Setup Steps:**

1. Create OIDC configuration files using ROSA CLI:
   ```bash
   rosa create oidc-config --managed=false --mode=manual
   ```

2. Upload the private key to AWS Secrets Manager:
   ```bash
   aws secretsmanager create-secret \
     --name rosa-oidc-private-key \
     --secret-string file://oidc-private-key.pem
   ```

3. Create the installer role (required for unmanaged OIDC):
   ```bash
   rosa create account-roles --mode=auto
   ```

4. Reference in Terraform variables.

**Pros:**
- Full control over private key
- Key stored in your AWS account
- Meets strict compliance requirements

**Cons:**
- You manage key security and rotation
- More complex setup
- Requires installer role to exist first

## External Authentication (HCP Only)

External authentication replaces the built-in OpenShift OAuth server with
direct integration to your corporate OIDC identity provider.

**Important Constraints:**
- HCP only (not available for Classic)
- Must be enabled at cluster creation
- Cannot be added to existing clusters
- Cannot be disabled once enabled
- Requires OpenShift 4.15.5+

### Enabling External Auth

```hcl
# tfvars
external_auth_providers_enabled = true
create_admin_user               = false  # OAuth server is replaced
```

### Post-Cluster Configuration

After the cluster is created, configure the external auth provider:

```bash
# Add external auth provider (example with Entra ID)
rosa create external-auth-provider \
  --cluster=my-cluster \
  --name=entra-id \
  --issuer-url=https://login.microsoftonline.com/{tenant-id}/v2.0 \
  --issuer-audiences=api://openshift \
  --claim-mapping-username-claim=preferred_username \
  --claim-mapping-groups-claim=groups \
  --console-client-id={client-id} \
  --console-client-secret={client-secret}

# Optional: Create break-glass credentials for emergency access
rosa create break-glass-credential --cluster=my-cluster
```

### Supported Identity Providers

External authentication has been tested with:
- Microsoft Entra ID (Azure AD)
- Red Hat build of Keycloak
- Any OpenID Connect compliant provider

### Benefits

- **Simplified authentication**: Use corporate identity tokens
- **Unified access control**: Leverage existing user/group management
- **Streamlined automation**: Reuse workflows across environments

## Decision Matrix

| Requirement | Recommended Configuration |
|-------------|--------------------------|
| Simple setup, single cluster | Managed per-cluster (default) |
| Multiple dev/test clusters | Pre-created managed OIDC |
| Compliance/audit requirements | Unmanaged (customer-managed) |
| Corporate SSO (HCP) | External auth + managed OIDC |
| GovCloud FedRAMP | Managed or unmanaged (both supported) |

## GovCloud Considerations

Both managed and unmanaged OIDC are fully supported in GovCloud. The OIDC
endpoints use GovCloud-specific S3 URLs:

- Commercial: `rh-oidc.s3.us-east-1.amazonaws.com/...`
- GovCloud: `rh-oidc.s3.us-gov-west-1.amazonaws.com/...`

For FedRAMP compliance:
- Unmanaged OIDC provides additional control and audit capabilities
- Customer-managed keys in AWS Secrets Manager follow your key management policies
- Both modes meet FedRAMP High requirements

## Troubleshooting

### OIDC Provider Not Found

If you see errors about OIDC provider not found when using pre-created config:

```
Error: oidc-provider not found
```

Ensure:
1. The `oidc_endpoint_url` is correct (without `https://` prefix)
2. The AWS IAM OIDC provider exists in your account
3. The thumbprint matches

### Operator Role Trust Policy Errors

If operator pods fail to assume IAM roles:

```bash
# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check thumbprint
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::ACCOUNT:oidc-provider/ENDPOINT
```

### External Auth Not Working

For external authentication issues:

```bash
# List external auth providers
rosa list external-auth-provider --cluster=my-cluster

# Verify break-glass credentials exist
rosa list break-glass-credential --cluster=my-cluster
```

## References

- [ROSA OIDC Overview](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/introduction_to_rosa/rosa-oidc-overview)
- [Creating ROSA with External Auth](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-sts-creating-a-cluster-ext-auth)
- [terraform-redhat/rosa-hcp Module](https://registry.terraform.io/modules/terraform-redhat/rosa-hcp/rhcs/latest)
