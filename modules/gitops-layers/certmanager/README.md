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

## Custom Ingress Integration

When a custom domain is configured, the cert-manager layer automatically creates a **scoped IngressController** that keeps user workload traffic isolated from the default ROSA ingress (which serves console, oauth, monitoring).

### What Gets Created

1. **IngressController** (`custom-apps`) -- scoped to your domain via `spec.domain`
2. **NLB** -- separate load balancer (private or public, configurable)
3. **Wildcard TLS certificate** -- issued by Let's Encrypt, auto-renewed by cert-manager
4. **Route53 wildcard CNAME** -- `*.yourdomain.com` pointing to the custom NLB (upsert)

### DNS Record Behavior

The Route53 wildcard CNAME (`*.apps.<domain>`) is created using **upsert** semantics
(`allow_overwrite = true`). This means:

- If the record **does not exist**, it is created pointing to the custom IngressController's NLB.
- If the record **already exists** (e.g., ROSA pre-creates `*.apps.<domain>` for its default ingress), Terraform takes ownership and **updates it** to point to the custom NLB instead.

This is the expected behavior when the custom ingress domain matches the cluster's default
apps domain. The custom IngressController replaces the default ROSA ingress for that domain,
serving routes with a valid Let's Encrypt wildcard certificate instead of the default
self-signed certificate.

On `terraform destroy`, Terraform removes the record. If the cluster is still running,
ROSA's ingress operator will recreate the default record on its own.

### Traffic Isolation

When a **separate custom domain** is used (different from the ROSA apps domain):

```
Default ROSA Ingress (untouched):
  *.apps.cluster-name.xxxx.openshiftapps.com
  -> console, oauth, monitoring, internal routes

Custom Ingress (cert-manager layer):
  *.yourdomain.com
  -> user workload routes only (scoped by domain + optional selectors)
```

When the **custom domain matches the ROSA apps domain** (e.g., `apps.example.com`):

```
Custom Ingress (replaces default for this domain):
  *.apps.example.com
  -> all routes on this domain, now served with Let's Encrypt TLS
  -> Route53 CNAME is upserted to point to the custom NLB

Default ROSA Ingress (still active):
  *.apps.cluster-name.xxxx.openshiftapps.com
  -> console, oauth, monitoring (via the cluster's built-in domain)
```

### Configuration

```hcl
# Custom ingress is enabled by default when certmanager has a domain
certmanager_ingress_enabled    = true      # default: true
certmanager_ingress_domain     = ""        # default: "apps.<hosted_zone_domain>"
certmanager_ingress_visibility = "private" # or "public"
certmanager_ingress_replicas   = 2

# Optional: additional scoping beyond domain-based matching
certmanager_ingress_route_selector     = {}  # e.g., { "ingress" = "custom-apps" }
certmanager_ingress_namespace_selector = {}  # e.g., { "apps-domain" = "custom" }
```

The `certmanager_hosted_zone_domain` is the **root Route53 zone** (e.g., `example.com`).
The `certmanager_ingress_domain` controls what the IngressController serves and defaults
to `apps.<root>`. This keeps zone management and ingress scoping cleanly separated.

### Creating Routes on the Custom Ingress

Routes matching the custom domain are automatically served by the custom IngressController:

```bash
# Routes with hostnames under the custom domain use the custom ingress
oc create route edge my-app \
  --service=my-app \
  --hostname=my-app.apps.example.com

# Routes under the default *.apps.cluster.openshiftapps.com domain
# continue to use the default ROSA ingress (unchanged)
```

If `certmanager_ingress_route_selector` is set, routes also need the matching labels:

```bash
oc label route my-app ingress=custom-apps
```

### Quick Verification

After deployment, verify the custom ingress is working end-to-end with a simple test app:

```bash
# 1. Create a test namespace
oc new-project test-custom-ingress

# 2. Deploy a simple web server
oc new-app --image=registry.access.redhat.com/ubi9/httpd-24:latest --name=hello-app

# 3. Create a route on the custom apps domain
oc create route edge hello-app \
  --service=hello-app \
  --hostname=hello.apps.example.com \
  --port=8080

# 4. Verify the route is using the custom IngressController
oc get route hello-app -o jsonpath='{.status.ingress[0].routerName}'
# Expected output: custom-apps

# 5. Test HTTPS (certificate should be valid, issued by Let's Encrypt)
curl -sv https://hello.apps.example.com 2>&1 | grep -E 'subject:|issuer:|HTTP/'

# 6. Clean up
oc delete project test-custom-ingress
```

If the route shows `routerName: custom-apps` and curl shows a valid Let's Encrypt
certificate, the full chain is working: cert-manager -> wildcard cert -> custom
IngressController -> NLB -> Route53 CNAME -> your app.

### Domain Flexibility

The `certmanager_hosted_zone_domain` is your root Route53 zone (e.g., `example.com`).
The `certmanager_ingress_domain` controls what the IngressController serves and defaults
to `apps.<root>`. Override it to use a different pattern:

| `certmanager_ingress_domain` | IngressController serves | Use Case |
|------------------------------|--------------------------|----------|
| `""` (default)               | `apps.example.com`       | **Recommended.** Apps subdomain (`myapp.apps.example.com`) |
| `"example.com"`              | `example.com`            | Root domain ingress (`myapp.example.com`) |
| `"dev.example.com"`          | `dev.example.com`        | Environment-scoped (`myapp.dev.example.com`) |

### Defaulting Namespaces to the Custom Ingress

To have all Routes in a namespace automatically use the custom ingress domain, label
the namespace. Combined with `certmanager_ingress_namespace_selector`, this scopes
which namespaces the custom IngressController watches:

```bash
# Label a namespace to be served by the custom ingress
oc label namespace my-project apps-domain=custom

# Then set the namespace selector in your tfvars:
# certmanager_ingress_namespace_selector = { "apps-domain" = "custom" }
```

Routes created in labeled namespaces with hostnames matching the custom domain are
automatically served by the custom IngressController with TLS from the wildcard cert.
Unlabeled namespaces continue to use the default ROSA ingress.

### Disabling the Custom Ingress

To use cert-manager for certificate management only (without a custom IngressController):

```hcl
certmanager_ingress_enabled = false
```

## Usage

### Basic (with existing hosted zone)

```hcl
enable_layer_certmanager    = true
certmanager_hosted_zone_id  = "Z0123456789ABCDEF"
certmanager_acme_email      = "platform-team@example.com"
```

### Create hosted zone + custom ingress + wildcard certificate

```hcl
enable_layer_certmanager       = true
certmanager_create_hosted_zone = true
certmanager_hosted_zone_domain = "example.com"   # Root zone
certmanager_acme_email         = "platform-team@example.com"

# Custom ingress (enabled by default, domain defaults to apps.example.com)
certmanager_ingress_visibility = "private"

# Wildcard certificate for the apps domain
certmanager_certificate_domains = [
  {
    name        = "apps-wildcard"
    namespace   = "openshift-ingress"
    secret_name = "custom-apps-default-cert"
    domains     = ["*.apps.example.com"]
  }
]
```

> **Important:** The certificate `secret_name` should be `custom-apps-default-cert` to match the IngressController's `defaultCertificate` reference.

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
| `certmanager_ingress_enabled` | Create a custom IngressController | `bool` | `true` | No |
| `certmanager_ingress_domain` | Ingress domain (empty = `apps.<root>`) | `string` | `""` | No |
| `certmanager_ingress_visibility` | NLB scope: `"private"` or `"public"` | `string` | `"private"` | No |
| `certmanager_ingress_replicas` | Router replicas for custom ingress | `number` | `2` | No |
| `certmanager_ingress_route_selector` | Additional route label selector | `map(string)` | `{}` | No |
| `certmanager_ingress_namespace_selector` | Namespace label selector | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `certmanager_role_arn` | IAM role ARN for cert-manager |
| `certmanager_hosted_zone_id` | Route53 hosted zone ID |
| `certmanager_hosted_zone_domain` | Hosted zone domain |
| `certmanager_hosted_zone_nameservers` | NS records (when zone is created) |
| `certmanager_ingress_enabled` | Whether custom IngressController was created |
| `certmanager_ingress_domain` | Domain served by the custom ingress |
| `certmanager_ingress_visibility` | NLB visibility (private/public) |
