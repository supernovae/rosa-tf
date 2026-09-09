# ROSA Terraform — 2.0 pre-release

**A reusable foundation for private OpenShift platforms on AWS commercial and GovCloud.**

Build Red Hat OpenShift Service on AWS (ROSA) Classic or Hosted Control Plane
(HCP) clusters with a consistent Terraform workflow, then add the platform
services your teams need: GitOps, observability, certificates, shared storage,
backup and recovery, virtualization, and AI. Start with a focused cluster and
grow deliberately—without assembling a different infrastructure project for
every environment.

[Quick start](#quick-start) · [Support matrix](#support-matrix) ·
[Platform layers](#platform-layers) · [Documentation](#documentation) ·
[RHCS capabilities](docs/RHCS-CAPABILITIES.md)

> **2.0 pre-release:** this is the next-generation, fresh-deployment baseline,
> using stable RHCS 1.7.8. The repository's 2.0 release is not yet approved or
> tagged. **Existing 1.x users should stay on their 1.x branches/tags. New users
> should choose a tagged 2.0 release once available**; until then, use this branch
> for evaluation and contribution. There is no supported in-place 1.x state
> upgrade. See [release readiness](docs/ROADMAP.md).

## Why this project

- **One approach across four deployment targets.** Shared modules and familiar
  environment roots bring consistency to commercial/GovCloud and Classic/HCP
  deployments while preserving their real architectural differences.
- **Security-conscious starting points.** Private cluster seeds, customer-managed
  KMS options, encrypted etcd, IMDSv2, deletion protection, and GovCloud FIPS
  defaults make important deployment choices visible from the beginning.
- **Platform services that fit together.** Opt-in layers connect cluster
  provisioning with day-two operations, including NetApp-backed VM storage,
  OADP recovery, trusted certificates, and workload onboarding through GitOps.
- **Native provider capabilities, not a parallel implementation.** Typed RHCS
  inputs expose cluster and pool features directly. A checked-in audit accounts
  for 21 resources and 16 data sources; CI checks schema and input-contract drift.
- **Flexible infrastructure and compute.** Create a VPC or bring an existing one,
  use separate HCP account IAM ownership, and add purpose-built worker pools for
  ARM, GPU, storage, or interruption-tolerant Spot workloads where supported.
- **An inspectable, repeatable delivery process.** Committed provider locks,
  reviewed Terraform plans, explicit layer ownership, regression tests, and
  enforced security checks help teams understand what they are deploying.

## Support matrix

These are the repository's four deployment targets and seed defaults, **not a
vendor certification or a guarantee that every feature is available in every
region**. Live acceptance for the 2.0 release remains in progress.

| Environment root | Control plane | Seed posture | Account IAM lifecycle |
| --- | --- | --- | --- |
| [Commercial HCP](environments/commercial-hcp/README.md) | Red Hat-hosted | Private; encrypted; on-demand base workers | Separate shared account root |
| [Commercial Classic](environments/commercial-classic/README.md) | In your AWS account | Private; encrypted; on-demand base workers | Cluster-scoped roles |
| [GovCloud HCP](environments/govcloud-hcp/README.md) | Red Hat-hosted | Private; FIPS; encrypted; zero-egress default | Separate shared account root |
| [GovCloud Classic](environments/govcloud-classic/README.md) | In your AWS account | Private; FIPS; encrypted; reviewed service egress | Cluster-scoped roles |

The pinned baseline is **Terraform 1.16.1 and RHCS 1.7.8**; other provider versions
and locks are documented in the [provider guide](docs/PROVIDER-UPGRADE.md).
Select an explicit OpenShift patch offered for your account, region, architecture,
and chosen layers. Seeds intentionally do not guess a universally supported
patch version.

Important capability boundaries:

- **ARM and mixed-architecture HCP pools:** place compatible workloads on
  Graviton workers alongside x86 pools; verify instance availability, images,
  and operator/operand support. See [machine pools](docs/MACHINE-POOLS.md) and
  [observability placement and economics](docs/OBSERVABILITY.md).
- **AutoNode / Red Hat build of Karpenter:** the packaged workflow is commercial
  HCP only and requires the documented OpenShift 4.22+ path plus regional/account
  eligibility. It does not imply GovCloud or Classic availability.
  See [AutoNode](docs/AUTONODE.md).
- **Zero egress:** GovCloud HCP seeds default to it. Private service endpoints,
  image mirrors, DNS, and workload connectivity still need preparation.
  See [zero-egress deployment](docs/ZERO-EGRESS.md).
- **Optional layers:** each has its own platform, architecture, catalog, storage,
  and permission requirements. For example, the current OADP layer does not
  accept OpenShift 4.18; virtualization and AI need additional support and
  hardware checks. Consult the layer guide before selecting a cluster version.

## Quick start

The core workflow is **choose a root → customize a seed → review a plan → apply**.
The same steps work for commercial and GovCloud clusters. Cloud resources incur
costs; these are evaluation instructions for the prerelease, not a shortcut
around account approval or production readiness.

### 1. Prepare access and choose your target

Have Terraform from [.terraform-version](.terraform-version), Git, AWS CLI, an
eligible ROSA account, and approved AWS/RHCS credentials ready. Use short-lived
AWS sessions. Inject commercial RHCS service-account inputs
(`TF_VAR_rhcs_client_id`, `TF_VAR_rhcs_client_secret`) or the GovCloud input
(`TF_VAR_ocm_token`) through your approved credential workflow—not committed
tfvars or pasted shell-history secrets.

```sh
git clone https://github.com/supernovae/rosa-tf.git
cd rosa-tf

# Choose ONE root. After release, check out an approved 2.0 tag first.
ROSA_ENV=commercial-hcp
# ROSA_ENV=govcloud-hcp
# ROSA_ENV=commercial-classic
# ROSA_ENV=govcloud-classic

aws sts get-caller-identity
terraform version
```

Confirm the AWS identity belongs to the intended commercial or GovCloud account.
Before initializing, configure an encrypted, access-controlled remote backend
with locking and recovery/versioning for each state. Give every cluster its own
state; keep HCP account state separate. Arrange access to the private API for
cluster administration and the later layer apply. Full prerequisites are in
[deployment](docs/DEPLOYMENT.md).

### 2. HCP only: prepare shared account roles

Skip this step for Classic. For HCP, provision the [account root](environments/account-hcp)
once for the intended account/region, or use existing compatible roles with an
explicit owner. Do not create or import roles already managed by another state.

```sh
# Run from the repository root, for an HCP target only.
# The selected name resolves to commercial.tfvars or govcloud.tfvars.
cp -n "environments/account-hcp/${ROSA_ENV%-*}.tfvars" \
  environments/account-hcp/private.auto.tfvars
```

Edit that private copy for your region, role prefix, and required KMS access.
Then review and apply the account changes:

```sh
umask 077
ROSA_ACCOUNT_PLANS=$(mktemp -d)
terraform -chdir=environments/account-hcp init -lockfile=readonly
terraform -chdir=environments/account-hcp plan -out="$ROSA_ACCOUNT_PLANS/account.tfplan"
terraform -chdir=environments/account-hcp show "$ROSA_ACCOUNT_PLANS/account.tfplan"
# After reviewing the account, permissions, and changes:
terraform -chdir=environments/account-hcp apply "$ROSA_ACCOUNT_PLANS/account.tfplan"
```

Keep these roles while any cluster depends on them. The HCP cluster roots consume
them using `account_role_prefix` or explicit role ARNs. Use a separate checkout
and backend configuration when switching accounts; do not reuse the account
root's private settings or initialized state across partitions.

### 3. Create your cluster

```sh
# Run from the repository root. -n preserves any existing private file.
cp -n "environments/$ROSA_ENV/cluster-dev.tfvars" \
  "environments/$ROSA_ENV/private.auto.tfvars"
```

Edit `environments/<your-root>/private.auto.tfvars`: choose your cluster name,
region, and an explicitly verified `openshift_version`; review worker capacity,
KMS, and network choices. For HCP, match the prepared account roles. Keep
`install_gitops = false` for this first apply. Private `*.auto.tfvars` files are
Git-ignored and loaded automatically by Terraform; keep credentials out of them.

For an existing network, follow [BYO-VPC](docs/BYO-VPC.md). For GovCloud HCP,
complete the [zero-egress prerequisites](docs/ZERO-EGRESS.md) before proceeding.

```sh
umask 077
ROSA_CLUSTER_PLANS=$(mktemp -d)
terraform -chdir="environments/$ROSA_ENV" init -lockfile=readonly
terraform -chdir="environments/$ROSA_ENV" validate
terraform -chdir="environments/$ROSA_ENV" plan -out="$ROSA_CLUSTER_PLANS/cluster.tfplan"
terraform -chdir="environments/$ROSA_ENV" show "$ROSA_CLUSTER_PLANS/cluster.tfplan"
# After reviewing the account, region, IAM, private networking, costs, and changes:
terraform -chdir="environments/$ROSA_ENV" apply "$ROSA_CLUSTER_PLANS/cluster.tfplan"
```

Saved plans can contain secrets. These examples keep them outside the checkout
in private temporary directories; protect and dispose of them through your
approved sensitive-artifact process. Treat state and bootstrap credentials as
privileged data too. A successful apply is the start of acceptance: verify API
access, trusted TLS, cluster health, identity, and workload scheduling.

### 4. Add platform services when the cluster is ready

Use the **same cluster root, private base, and state** for phase two. From a runner
with private API access, review the root's `gitops-dev.tfvars` or
`gitops-prod.tfvars` overlay and select the [layer examples](examples/README.md)
you need. Verify their prerequisites, then create and review a new saved plan
with the chosen overlays. Nothing is enabled merely by copying the cluster seed.

Terraform owns the selected platform resources; Argo CD owns explicitly delegated
workloads. Keep those boundaries clear—do not point Argo CD at Terraform-owned
layer templates or let both tools reconcile the same object. The
[GitOps onboarding guide](docs/GITOPS.md) covers trusted repositories, identity,
namespace boundaries, and safe workload delivery.

## Platform layers

Build beyond the cluster with opt-in capabilities and operational guides, not
just operator installation. Enable only what your workloads need.

| Capability | What it adds | Guide |
| --- | --- | --- |
| GitOps | Argo CD platform integration and controlled workload onboarding | [GitOps](docs/GITOPS.md) |
| Observability | Metrics, logs, alerts, dashboards, and ARM placement guidance | [Observability](docs/OBSERVABILITY.md) |
| Certificates | Certificate automation and scoped issuer/ingress configuration | [Cert-manager](modules/gitops-layers/certmanager/README.md) |
| Component routes | Native console/downloads routes; OAuth routes on Classic | [Component routes](docs/COMPONENT-ROUTES.md) |
| NetApp storage | Trident-backed container and VM storage with explicit backend ownership | [NetApp](docs/NETAPP-STORAGE.md) |
| EFS storage | Shared application files with private access and backup integration | [EFS](docs/EFS-STORAGE.md) |
| Virtualization | VM deployment integrated with supported storage and recovery paths | [Virtualization](docs/VIRTUALIZATION.md) |
| Backup and recovery | OADP application and VM backup, prerequisites, and restore workflows | [OADP](docs/OADP.md) |
| OpenShift AI | An opt-in AI platform layer with hardware and support prerequisites | [OpenShift AI](modules/gitops-layers/openshift-ai/README.md) |

For compute configuration, see [machine pools](docs/MACHINE-POOLS.md),
[AutoNode](docs/AUTONODE.md), and the [native provider examples](examples/rhcs-companion-resources/README.md).
For observability data protection, see [AWS recovery options](docs/OBSERVABILITY-AWS-RECOVERY.md).

## Quality, security, and operations

The project combines reusable modules with checks that help keep their contracts
honest: provider-schema inventory, root/module input consistency, Terraform
validation and mocked regression tests, layer contracts, example checks,
documentation links, vulnerability scanning, and secret detection. CI Actions
use immutable references, and security failures are not silently converted into
successful builds. Mock tests do not provision cloud infrastructure.

Deployment protections include deletion protection, verified TLS, no forced
Kubernetes manifest takeover, and no automatic VPC orphan deletion. Retained
storage is not a backup: plan for restore testing, identity recovery, credential
rotation, and deliberate retirement from the beginning.

GovCloud/FIPS/zero-egress settings help establish a security-conscious foundation;
**they do not confer FedRAMP authorization or certify a workload**. Account
controls, vendor support, operational evidence, and live acceptance remain the
deployment owner's responsibility. See [security](docs/SECURITY.md),
[FedRAMP considerations](docs/FEDRAMP.md), and [operations](docs/OPERATIONS.md).

## Documentation

| Start with | Then explore |
| --- | --- |
| [Deployment workflow](docs/DEPLOYMENT.md) | [Examples and overlay ordering](examples/README.md) |
| [RHCS capability and ownership audit](docs/RHCS-CAPABILITIES.md) | [Provider baseline and updates](docs/PROVIDER-UPGRADE.md) |
| [BYO-VPC networking](docs/BYO-VPC.md) | [Zero egress](docs/ZERO-EGRESS.md) · [Security groups](docs/SECURITY-GROUPS.md) |
| [GitOps onboarding](docs/GITOPS.md) | [Layer architecture](docs/GITOPS-LAYERS-GUIDE.md) |
| [Day-two operations](docs/OPERATIONS.md) | [Security](docs/SECURITY.md) · [Release roadmap](docs/ROADMAP.md) |

## Contributing and license

Contributions that improve deployment clarity, native provider coverage,
regression tests, and real-world acceptance evidence are welcome. Start with
[the contribution guide](docs/CONTRIBUTING.md) and
[the 2.0 release checklist](docs/ROADMAP.md). Report reproducible problems with
the target root and versions, never credentials, state, or saved plans.

Licensed under the [Apache License 2.0](LICENSE).
