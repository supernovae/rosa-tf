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
