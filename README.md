# ROSA Terraform — 2.0 preparation

Deploy private ROSA Classic or Hosted Control Plane clusters in AWS commercial
and GovCloud regions, then explicitly enable reviewed platform/GitOps layers.

**This branch is development-only.** It pins stable RHCS `1.7.8` while we
prepare 2.0. No 2.0 release is approved or tagged. The release workflow blocks
tagging until verified provider locks and release approval are in place. See [release readiness](docs/ROADMAP.md).

2.0 is a **fix-forward fresh-deployment baseline**, not a supported in-place
upgrade from 1.x. Do not point it at existing production state or apply it to
existing data without an independently reviewed transition/recovery plan.
Historical 1.x tags retain their original behavior and documentation.

## Start here

1. Read [deployment prerequisites and the two-phase workflow](docs/DEPLOYMENT.md).
2. Select an environment root and copy its seed into an ignored private tfvars
   file. Set an explicitly verified regional OpenShift patch; there is no stale
   default version. Keep credentials out of tfvars/Git.
3. Review [RHCS capabilities and native lifecycle behavior](docs/RHCS-CAPABILITIES.md).
4. Review a saved plan before applying cluster infrastructure. Verify endpoints,
   CA trust, authentication and catalogs before the separate platform-layer apply.

| Root | Model | Baseline |
| --- | --- | --- |
| [commercial-classic](environments/commercial-classic/README.md) | Customer-account control plane | Private, encrypted seeds |
| [commercial-hcp](environments/commercial-hcp/README.md) | Hosted control plane | Private, on-demand base workers |
| [govcloud-classic](environments/govcloud-classic/README.md) | Customer-account control plane | Private, FIPS required |
| [govcloud-hcp](environments/govcloud-hcp/README.md) | Hosted control plane | Private, FIPS, zero-egress default |

HCP account-wide IAM roles are a separate [account root](environments/account-hcp).
Keep account lifecycle separate from cluster lifecycle. Shared inputs are not a
claim that every operator, instance type or preview feature is supported in
every region. Confirm support and capacity before provisioning.

## Platform layers

Terraform owns platform configuration; Argo CD owns explicitly delegated
workloads. Do not give both tools ownership of the same object. Layers are
opt-in; forced Kubernetes field ownership is disabled repository-wide.

| Capability | Guide |
| --- | --- |
| Secure GitOps and workload onboarding | [GitOps](docs/GITOPS.md) |
| Metrics, logs and alerts | [Observability](docs/OBSERVABILITY.md) |
| Certificates and scoped application ingress | [Cert-manager](modules/gitops-layers/certmanager/README.md) |
| Native console/downloads/OAuth routes | [Component routes](docs/COMPONENT-ROUTES.md) |
| NetApp container/VM storage | [NetApp](docs/NETAPP-STORAGE.md) |
| EFS shared application files | [EFS](docs/EFS-STORAGE.md) |
| VM deployment | [Virtualization](docs/VIRTUALIZATION.md) |
| Application and VM recovery | [OADP](docs/OADP.md) |
| OpenShift AI | [AI layer](modules/gitops-layers/openshift-ai/README.md) |
| ARM, autoscaling and interruption-tolerant Spot pools | [Machine pools](docs/MACHINE-POOLS.md) |

## Safety and trust

- Terraform 1.16.1 and committed cross-platform provider locks; see
  [provider baseline](docs/PROVIDER-UPGRADE.md).
- Cluster deletion protection and IMDSv2; private development/production seeds.
- No TLS verification bypass or forced manifest takeover.
- No automatic VPC orphan deletion. The inventory helper is read-only.
- Immutable CI Action references, real scanner failures, secret checks and
  module/contract tests. Scans do not establish compliance or live support.
- Retained storage still requires backups and tested restores. Lifecycle
  protection does not replace account controls, RBAC or recovery credentials.

See [operations](docs/OPERATIONS.md), [security](docs/SECURITY.md),
[FedRAMP considerations](docs/FEDRAMP.md), [examples](examples/README.md) and
[contributing](docs/CONTRIBUTING.md). No infrastructure is deployed by CI tests.
