# GovCloud ROSA Classic

This is a **2.0 development / fix-forward** root, not a supported 1.x upgrade.
Read [deployment and prerequisites](../../docs/DEPLOYMENT.md) before planning.
RHCS is pinned to stable `1.7.8`. Repository 2.0 release readiness remains
unapproved; native capabilities are documented in [the audit](../../docs/RHCS-CAPABILITIES.md).

## Deployment contract

- Supply an explicitly verified regional `openshift_version` in a private base tfvars file; seeds deliberately do not guess a patch release.
- Apply `cluster-dev.tfvars` or `cluster-prod.tfvars` first, then the corresponding GitOps overlay with only required layers enabled.
- Seeds use private endpoints, three workers, customer-managed KMS keys, encrypted etcd, deletion protection and no public jump host or VPN.
- Use GovCloud credentials, regional STS and the aws-us-gov partition. FIPS and private access cannot be disabled in this root.
- Classic control-plane and worker resources reside in your account. Budget and approve their capacity and required service egress.
- Review the network path, required service endpoints and workload egress explicitly.
- Manage layers only from a runner that can reach the private API. Protect Terraform state, plans and bootstrap credentials; remove bootstrap access after establishing managed identity.

## Guides

- [Examples and overlay ordering](../../examples/README.md)
- [Machine pools and opt-in Spot](../../docs/MACHINE-POOLS.md)
- [Native component routes](../../docs/COMPONENT-ROUTES.md)
- [GitOps ownership and operations](../../docs/GITOPS.md)
- [Zero egress](../../docs/ZERO-EGRESS.md)
- [Security](../../docs/SECURITY.md) and [FedRAMP responsibilities](../../docs/FEDRAMP.md)
- [Operations and deliberate decommission](../../docs/OPERATIONS.md)

A successful Terraform validation is not evidence of regional service eligibility,
operator support, successful installation or recoverability. Complete the
[release acceptance checklist](../../docs/ROADMAP.md) on the intended target.
