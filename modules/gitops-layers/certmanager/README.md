# Cert-Manager GitOps Layer

This module provides automated TLS certificate lifecycle management for ROSA clusters using the **OpenShift cert-manager operator** and **Let's Encrypt** with DNS01 challenges via Route53.

## Overview

The cert-manager layer:

1. **Installs** the OpenShift cert-manager operator from OperatorHub
2. **Configures** IRSA (IAM Roles for Service Accounts) for Route53 access
3. **Creates** Let's Encrypt ClusterIssuers (production + staging)
4. **Optionally creates** Certificate resources for specified domains
5. **Optionally installs** the OpenShift Routes integration for automatic TLS

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Terraform (this module)                         │
│                                                  │
│  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ IAM Role     │  │ Route53 Hosted Zone      │ │
│  │ (IRSA)       │  │ (optional create)        │ │
│  └──────┬───────┘  └──────────┬───────────────┘ │
└─────────┼──────────────────────┼─────────────────┘
          │                      │
          ▼                      ▼
┌─────────────────────────────────────────────────┐
│  OpenShift Cluster                               │
│                                                  │
│  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ cert-manager │  │ ClusterIssuer            │ │
│  │ operator     │──│ (Let's Encrypt DNS01)    │ │
│  └──────────────┘  └──────────┬───────────────┘ │
│                               │                  │
│                               ▼                  │
│                    ┌──────────────────────────┐  │
│                    │ Certificate resources    │  │
│                    │ (auto-renewed by LE)     │  │
│                    └──────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Prerequisites

- **Outbound internet access** - DNS01 challenge requires HTTPS to Let's Encrypt ACME servers
- **Route53 hosted zone** - Either provide an existing zone ID or let the module create one
- **ROSA cluster with STS** - OIDC provider is required for IRSA
- **NOT compatible with zero-egress clusters** - Use manually provided certificates instead

## Certificate Lifecycle

When using Let's Encrypt (default):

- cert-manager handles **all certificate lifecycle** automatically
- Certificates are valid for **90 days**
- Auto-renewal triggers **30 days before expiry**
- DNS01 challenge uses Route53 TXT records (no inbound HTTP needed)
- Works on both **public and private clusters** (only needs outbound HTTPS)

When using `cert_mode=provided` (zero-egress):

- **Users must manage certificate lifecycle manually**
- Provide TLS certificates and keys directly to the ingress controller
- Monitor certificate expiry dates
- Renew certificates before they expire

## DNS01 Challenge Flow

1. cert-manager requests a certificate from Let's Encrypt
2. Let's Encrypt issues a DNS01 challenge (expects a TXT record)
3. cert-manager creates the TXT record in Route53 (using IRSA credentials)
4. Let's Encrypt verifies the TXT record
5. Certificate is issued and stored as a Kubernetes Secret
6. cert-manager cleans up the TXT record

## IAM Permissions

The IAM role created by this module has least-privilege Route53 access:

- `route53:GetChange` - Check DNS propagation status
- `route53:ChangeResourceRecordSets` - Create/delete TXT records (scoped to hosted zone)
- `route53:ListResourceRecordSets` - List records (scoped to hosted zone)
- `route53:ListHostedZonesByName` - Discover hosted zones

## Routes Integration

When `certmanager_enable_routes_integration = true` (default), you can annotate OpenShift Routes for automatic TLS:

```bash
oc annotate route my-app \
  cert-manager.io/issuer-kind=ClusterIssuer \
  cert-manager.io/issuer-name=letsencrypt-production
```

This triggers cert-manager to:
1. Request a certificate for the Route's hostname
2. Store it as a Secret
3. Configure the Route's TLS termination

## DNS Delegation

When using `certmanager_create_hosted_zone = true`, Terraform creates a Route53 hosted zone with a **unique set of 4 nameservers**. Your domain registrar (Squarespace, GoDaddy, Namecheap, etc.) must be updated to delegate DNS to these nameservers before cert-manager can issue certificates.

### Understanding the Workflow

There is an intentional ordering dependency:

1. **`terraform apply`** creates the hosted zone, cluster, cert-manager, and ClusterIssuers
2. cert-manager immediately attempts to issue certificates via DNS01 challenges
3. **These will fail** until DNS delegation is complete -- this is expected
4. You update your registrar with the nameservers from Terraform output
5. DNS propagates (typically 15-60 minutes, can take up to 48 hours)
6. cert-manager retries and successfully issues certificates

> **If you provide an existing hosted zone** (`certmanager_hosted_zone_id`), DNS delegation is already done and cert-manager will work immediately after apply. This is the simplest path if you manage DNS ahead of time.

### Step 1: Get the Nameservers

After `terraform apply` completes:

```bash
# Get the Route53 nameservers for the new hosted zone
terraform output certmanager_hosted_zone_nameservers
```

Output example:
```
[
  "ns-1234.awsdns-26.org",
  "ns-567.awsdns-10.net",
  "ns-890.awsdns-47.co.uk",
  "ns-12.awsdns-01.com",
]
```

### Step 2: Update Your Domain Registrar

Set the nameservers at your registrar for the domain (e.g., `apps.example.com`):

| Registrar | Where to Update |
|-----------|----------------|
| **Squarespace** | Domains > your domain > DNS Settings > Custom nameservers |
| **GoDaddy** | Domain Settings > Nameservers > Change |
| **Namecheap** | Domain List > Manage > Nameservers > Custom DNS |
| **Cloudflare** | (must use full zone transfer or CNAME setup) |
| **AWS Route53** (parent zone) | Add NS record for the subdomain |

> **Subdomain delegation:** If you're delegating a subdomain like `apps.example.com` and the parent zone (`example.com`) is already in Route53, add an NS record set in the parent zone instead of changing registrar nameservers.

### Step 3: Verify DNS Propagation

```bash
# Check if nameservers are responding (replace with your domain)
dig +short NS apps.example.com

# Expected: the 4 Route53 nameservers from Step 1
# If you see your old nameservers, propagation is still in progress
```

### Step 4: Force cert-manager to Retry

cert-manager has an exponential backoff that can delay retries up to hours after initial failures. Once DNS is live, force an immediate retry:

```bash
# Option A: Delete and recreate the CertificateRequest (fastest)
# List pending certificate requests
oc get certificaterequests -A

# Delete the failed request -- cert-manager will create a new one immediately
oc delete certificaterequest <name> -n <namespace>

# Option B: Annotate the Certificate to trigger reconciliation
oc annotate certificate <name> -n <namespace> \
  cert-manager.io/manual-trigger="$(date +%s)" --overwrite

# Option C: Restart cert-manager (nuclear option, retries everything)
oc rollout restart deployment cert-manager -n cert-manager
```

### Step 5: Verify Certificate Issuance

```bash
# Check certificate status
oc get certificates -A

# Expected: READY = True
# NAME             READY   SECRET              AGE
# apps-wildcard    True    apps-wildcard-tls   5m

# If still not ready, check the challenge status
oc get challenges -A
oc describe challenge <name> -n <namespace>
```

### DNSSEC DS Record (Optional)

If `certmanager_enable_dnssec = true` (default), you should also add the DS record to your registrar to complete the DNSSEC chain of trust:

```bash
terraform output certmanager_dnssec_ds_record
```

Add this as a **DS record** at your registrar. This is not required for cert-manager to work -- it protects against DNS spoofing attacks.

### Troubleshooting DNS Delegation

| Symptom | Cause | Fix |
|---------|-------|-----|
| `dig NS apps.example.com` returns old nameservers | DNS propagation not complete | Wait, or flush local DNS cache (`sudo dscacheutil -flushcache` on macOS) |
| Challenge stuck in `pending` state | DNS not resolving | Verify nameservers with `dig`, check registrar settings |
| `ACME server error: dns problem` | Route53 zone not reachable | Confirm NS records propagated; try `dig @ns-1234.awsdns-26.org apps.example.com` |
| Certificate shows `False` READY after DNS is working | cert-manager backoff | Force retry (Step 4 above) |
| `Forbidden: route53:ChangeResourceRecordSets` | IAM role issue | Verify OIDC provider and role trust policy |

## Usage

### Basic (with existing hosted zone)

```hcl
enable_layer_certmanager    = true
certmanager_hosted_zone_id  = "Z0123456789ABCDEF"
certmanager_acme_email      = "platform-team@example.com"
```

### Create hosted zone + wildcard certificate

```hcl
enable_layer_certmanager       = true
certmanager_create_hosted_zone = true
certmanager_hosted_zone_domain = "apps.example.com"
certmanager_acme_email         = "platform-team@example.com"

certmanager_certificate_domains = [
  {
    name        = "apps-wildcard"
    namespace   = "openshift-ingress"
    secret_name = "apps-wildcard-tls"
    domains     = ["*.apps.example.com"]
  }
]
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `enable_layer_certmanager` | Enable the cert-manager layer | `bool` | `false` | No |
| `certmanager_hosted_zone_id` | Existing Route53 zone ID | `string` | `""` | When not creating |
| `certmanager_hosted_zone_domain` | Domain for the hosted zone | `string` | `""` | When creating |
| `certmanager_create_hosted_zone` | Create a new hosted zone | `bool` | `false` | No |
| `certmanager_acme_email` | Let's Encrypt registration email | `string` | `""` | Yes (when enabled) |
| `certmanager_certificate_domains` | Certificate resources to create | `list(object)` | `[]` | No |
| `certmanager_enable_routes_integration` | Install Routes integration | `bool` | `true` | No |

## Outputs

| Name | Description |
|------|-------------|
| `certmanager_role_arn` | IAM role ARN for cert-manager |
| `certmanager_hosted_zone_id` | Route53 hosted zone ID |
| `certmanager_hosted_zone_domain` | Hosted zone domain |
| `certmanager_hosted_zone_nameservers` | NS records (when zone is created) |
