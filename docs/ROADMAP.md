# Roadmap

This document tracks the status of features in this module.

## Feature Status

| Feature | Status | Notes |
|---------|--------|-------|
| VPC with Multi-AZ | ✅ Stable | 3-AZ deployment with NAT/TGW/Proxy egress options |
| IAM Roles (Classic) | ✅ Stable | Cluster-scoped roles, clean teardown |
| IAM Roles (HCP) | ✅ Stable | Shared account layer, per-cluster operator roles |
| IAM Lifecycle Management | ✅ Stable | Separate account/cluster layers for HCP multi-cluster |
| OIDC Configuration | ✅ Stable | Managed, unmanaged, or pre-created OIDC support |
| External Auth (HCP) | 🚧 WIP | External OIDC IdP for user authentication |
| ROSA Classic Cluster | ✅ Stable | Private/public clusters, FIPS optional, STS mode |
| ROSA HCP Cluster | ✅ Stable | Hosted control plane, ~15min provisioning |
| Zero-Egress HCP | ✅ Stable | Air-gapped clusters with no outbound internet |
| ECR Integration | ✅ Stable | Private container registry with VPC endpoints |
| KMS Encryption | ✅ Stable | Separate keys for cluster and infrastructure |
| Jump Host (SSM) | ✅ Stable | SSM-enabled access to private cluster |
| HTPasswd Authentication | ✅ Stable | cluster-admin user with Terraform-managed password |
| Client VPN | ✅ Stable | Optional OpenVPN-compatible VPN for direct access |
| Machine Pools (Classic) | ✅ Stable | Additional worker pools with GPU/spot support |
| Machine Pools (HCP) | ✅ Stable | GPU/highmem pools, n-2 version constraint |
| Cluster Autoscaler | ✅ Stable | Automatic node scaling for Classic and HCP |
| Backup/Restore (OADP) | ✅ Stable | GitOps layer with S3 backend, configurable retention |
| Monitoring/Logging | ✅ Stable | Prometheus + Loki with S3 backend, 30-day retention |
| GitOps Layers Framework | ✅ Stable | Composable Day 2 operations via ArgoCD |
| BYO-VPC (Multi-Cluster) | ✅ Stable | Deploy into existing VPC, AZ inference, CIDR planning. See [BYO-VPC.md](BYO-VPC.md) |
| BYO-VPC Subnet Helper | ✅ Stable | Standalone helper to create subnets in existing VPC. See [helpers/byo-vpc-subnets/](../helpers/byo-vpc-subnets/) |
| Custom Ingress | 🚧 WIP | Secondary ingress controller - not fully tested |

## Known Issues

### GovCloud HCP Billing Account

**Status:** Workaround in place, awaiting upstream fix

**Issue:** GovCloud HCP clusters require `aws_billing_account_id` to be null, while Commercial HCP clusters require it to be set. This is a limitation in the OCM/ROSA CLI that will be resolved in a future release.

**Current Behavior:**
| Environment | Billing Account | Notes |
|-------------|-----------------|-------|
| Commercial HCP | Auto-detected | Uses deployment account if not specified |
| GovCloud HCP | Set to null | Billing association not supported |

**Workaround:** The `is_govcloud` variable in the rosa-hcp module controls this behavior:
- `is_govcloud = true`: Billing account is always null (GovCloud)
- `is_govcloud = false`: Billing account defaults to deployment account (Commercial)

**Resolution:** Once OCM/ROSA CLI supports GovCloud billing, we will:
1. Update the module to auto-detect based on AWS partition
2. Remove the `is_govcloud` workaround
3. Allow explicit billing account for both environments

## Network Prerequisites (Firewall & Proxy)

ROSA clusters require outbound access to several Red Hat and AWS endpoints during installation and at runtime. Before deploying -- especially into a BYO-VPC or a network with restricted egress -- ensure that the required URLs and ports are allowed through your firewall or proxy.

### Required Documentation

| Cluster Type | Firewall/URL Reference |
|---|---|
| ROSA Classic | [AWS firewall prerequisites](https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa_getting_started_iam/rosa-aws-prereqs.html#osd-aws-privatelink-firewall-prerequisites_prerequisites) |
| ROSA HCP | [AWS firewall prerequisites (HCP)](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-aws-prereqs.html#osd-aws-privatelink-firewall-prerequisites_rosa-hcp-aws-prereqs) |

### Key Endpoints

At a minimum, the cluster needs outbound HTTPS (443) access to:

- `registry.redhat.io` / `quay.io` -- container image registries
- `api.openshift.com` (Commercial) or `api.openshiftusgov.com` (GovCloud) -- ROSA/OCM API
- `sso.redhat.com` -- Red Hat SSO authentication
- AWS service endpoints (S3, EC2, ELB, STS, etc.) -- varies by region and partition

### Cluster-Wide Proxy

If your network uses a proxy for outbound access instead of NAT/TGW, configure it in your `tfvars`:

```hcl
http_proxy  = "http://proxy.example.com:3128"
https_proxy = "http://proxy.example.com:3128"
no_proxy    = ".cluster.local,.svc,10.128.0.0/14,172.30.0.0/16"
additional_trust_bundle = file("corporate-ca-bundle.pem")  # if proxy uses custom CA
```

> **Zero-egress HCP clusters** do not require firewall rules or proxy configuration -- they use AWS PrivateLink and VPC endpoints exclusively. However, you must still ensure the required VPC endpoints are created. See the zero-egress example tfvars for details.

### BYO-VPC Considerations

When deploying into a BYO-VPC, you are responsible for ensuring the VPC's networking meets these requirements. The module does not create or modify firewall rules, NACLs, or proxy configurations in the existing VPC. See [BYO-VPC.md](BYO-VPC.md) for full details.

## GitOps Layers Framework

The GitOps Layers Framework provides a composable architecture for Day 2 operations, bridging Terraform (infrastructure) with ArgoCD (operations).

### Architecture

```
Terraform (Day 0/1)                    ArgoCD (Day 2)
       │                                     │
       │ Creates:                            │
       │ • AWS resources (S3, IAM, etc.)     │
       │ • ConfigMap bridge                  │
       │ • GitOps operator                   │
       ▼                                     ▼
┌─────────────────────┐           ┌─────────────────────┐
│ rosa-gitops-config  │           │ ApplicationSet      │
│ ConfigMap           │──────────▶│ manages layers      │
│                     │           │ based on flags      │
└─────────────────────┘           └─────────────────────┘
```

### Available Layers

| Layer | Description | Terraform Dependencies |
|-------|-------------|----------------------|
| `terminal` | Web Terminal operator | None |
| `oadp` | OpenShift API for Data Protection | S3 bucket, IAM role |
| `virtualization` | OpenShift Virtualization (KubeVirt) | Bare metal machine pool |
| `monitoring` | Prometheus + Loki logging stack | S3 bucket, IAM role |

### Usage

```hcl
# Enable GitOps with layers
install_gitops = true

# Layer 0: Web Terminal (enabled by default)
enable_layer_terminal = true

# Layer 1: OADP backup/restore
enable_layer_oadp = true
oadp_backup_retention_days = 30

# Layer 2: Virtualization (bare metal via machine_pools)
enable_layer_virtualization = true
# See examples/ocpvirtualization.tfvars for machine_pools config

# Layer 3: Monitoring and Logging
enable_layer_monitoring = true
monitoring_retention_days = 30  # Production (7 for dev)
```

### Custom Layers

Users can use their own GitOps repository instead of the reference implementations:

```hcl
gitops_layers_repo = "https://github.com/my-org/my-rosa-layers.git"
gitops_layers_path = "layers"
gitops_layers_revision = "main"
```

See [gitops-layers/README.md](gitops-layers/README.md) for layer structure and customization.

## Work in Progress

### Custom Ingress (modules/custom-ingress)

**Status:** Work in Progress - Not fully tested

This module is intended to create a secondary ingress controller for custom domains. The core logic is in place but has not been validated in a production environment.

**Known limitations:**
- Certificate management not fully implemented
- DNS integration untested
- Load balancer configuration may need adjustments for GovCloud

**Use at your own risk.** Contributions and testing feedback welcome.

## ROSA HCP Support

### Architecture Differences

| Component | Classic | HCP |
|-----------|---------|-----|
| Control Plane | Customer managed | Red Hat managed |
| IAM Policies | Customer managed | AWS managed |
| Account Roles | 4 | 3 (no ControlPlane) |
| Operator Roles | 6-7 | 8 |
| Provisioning | ~40 min | ~15 min |
| Machine Pool Versions | Independent | n-2 of control plane |

### HCP Version Drift

HCP machine pools must stay within **n-2 minor versions** of control plane:

```
Control Plane: 4.16.x
Valid:   4.16.x, 4.15.x, 4.14.x
Invalid: 4.13.x (too old)
```

**Upgrade sequence**: Control plane first, then machine pools.

See [modules/cluster/machine-pools-hcp/README.md](../modules/cluster/machine-pools-hcp/README.md) for details.

### GovCloud HCP Requirements

GovCloud HCP enforces additional security controls:

| Control | GovCloud | Commercial |
|---------|----------|------------|
| FIPS | **Mandatory** | Optional |
| Private Cluster | **Mandatory** | Optional |
| KMS Encryption | **Mandatory** | Optional |
| API Endpoint | api.openshiftusgov.com | api.openshift.com |

These are hardcoded in `environments/govcloud-hcp/` and cannot be disabled.

## Planned Features

Features under consideration for future releases:

### Infrastructure
- [x] Cluster autoscaler configuration - See `cluster_autoscaler_enabled` in cluster modules
- [ ] External Secrets Operator integration
- [ ] Cert-Manager with Let's Encrypt
- [x] Multi-cluster in single VPC - BYO-VPC support with subnet helper. See [BYO-VPC.md](BYO-VPC.md)
- [ ] Unify default worker pool into `machine_pools` variable once HCP supports 0-worker pools (~4.22 timeframe)

### Security & Documentation
- [ ] Admin password rotation procedures
- [ ] IAM trust boundary diagrams
- [ ] MFA requirement documentation
- [ ] OIDC security model deep-dive

### GitOps Layers
- [x] Monitoring and Logging - Prometheus + Loki with S3 backend, see [gitops-layers/layers/monitoring/](../gitops-layers/layers/monitoring/)
- [ ] Service Mesh (OpenShift Service Mesh)
- [ ] Compliance Operator
- [ ] Advanced Cluster Security (ACS)
- [ ] Consolidate `gitops_resources` + `gitops` into a single wrapper module to reduce ~80 lines of passthrough per environment

### Operations
- [x] Backup/restore procedures - OADP GitOps layer with S3, see [gitops-layers/layers/oadp/](../gitops-layers/layers/oadp/)
- [ ] Disaster recovery runbooks
- [x] Upgrade procedures guide - See [OPERATIONS.md](OPERATIONS.md#upgrade-cluster) for Classic and HCP upgrade workflows

## Contributing

If you'd like to help complete WIP features or suggest new ones, please:

1. Open an issue to discuss the feature
2. Submit a PR with tests and documentation
3. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
