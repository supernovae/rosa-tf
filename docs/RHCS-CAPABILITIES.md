# RHCS capability and ownership audit

Baseline: stable RHCS **1.7.8**, published 2026-09-09. The final release has the
same Git tree as prerelease.2; verified stable binaries/locks replace prerelease
artifacts. Repository 2.0 readiness is still unapproved. [Provider source](https://github.com/terraform-redhat/terraform-provider-rhcs/tree/v1.7.8).

## Coverage without a second provider implementation

[The machine-readable inventory](rhcs-capabilities.json) accounts for all 21 RHCS
resources, 16 read-only data sources and every input field/type, including nested fields. CI compares it
with the installed provider. All top-level fields of the two specialized cluster
and two machine-pool resources are wired or explicitly fixed by policy; the
duplicate provider-generated admin switch is replaced by our named native
`admin_credentials` bootstrap. Schema presence does not establish service support.

| Owner | Capabilities |
| --- | --- |
| Cluster modules and `cluster_options` | Cluster lifecycle, native version/channel upgrades, tags, timeouts, DNS/shared-VPC references, STS, proxy; HCP registry policy, audit/log forwarding, initial-pool scaling and Spot interruption queue |
| Machine-pool modules | Native scaling/Spot, placement, tags and extra security groups; HCP reservations, image type, per-pool repair, tuning/kubelet references, acknowledgments and drain time |
| Dedicated existing modules | Account/OIDC roles/configuration, Classic autoscaler, native default-ingress component routes |
| Native companion resources | IdPs/group membership, emergency access, DNS reservation, digest mirrors, kubelet/tuning configuration and Day-2 log forwarders |
| Deliberately unavailable | Generic non-specialized cluster replacement; HCP cluster-wide autoscaler endpoint documented unavailable in this provider |

Companion resources are composed directly, not rewrapped into a giant opaque
`any` object. See [the native example](../examples/rhcs-companion-resources).
Separate identity secrets/emergency access from routine cluster lifecycle. Do
not give Terraform and GitOps ownership of the same IdP, mirror or log forwarder.
HCP external-auth enablement is not IdP configuration; its provider configuration
API is not present in this provider inventory. Do not substitute an OAuth IdP.

## Native names, types and safety boundaries

`cluster_options` exposes native provider names and nested types. Its canonical
definition lives in the architecture module; CI checks identical root copies.
This avoids independently evolving handwritten input contracts. The two distinct
cluster resources are not artificially merged: Classic and HCP differ materially.
CI also checks that each root's machine-pool type matches its architecture module.
The unused Classic per-pool `attach_ecr_policy` seed option is removed; Classic
worker-role permissions remain a cluster IAM concern, not a machine-pool feature.

Use `cluster_options.channel` OR the existing `channel_group`; an explicit
channel takes precedence and omits channel_group from configuration. `tags` now
uses native AWS resource tags; custom OCM properties belong in
`cluster_options.properties`, not in AWS tags. Reserved identity/zero-egress
properties cannot be overridden. STS external IDs must match account-role trust.

Creation-only DNS/shared-VPC, initial-pool and logging options remain subject to
RHCS lifecycle rules. Shared-VPC roles/zones must already exist in the correct
partition; these inputs do not build a shared network or grant missing permissions.
Keep default worker-pool ownership with one resource: initial cluster fields are
creation settings. Import the default pool into the native pool resource before
managing its Day-2 scaling; do not create a second pool with the same name.

IMDSv2, permission checks and managed CNI stay enabled. Cluster deletion waits and
pool deletion errors cannot be bypassed. Registry TLS cannot be disabled: supply
trusted CA material instead. Audit roles, SQS queue permissions/events/region,
allowlists and mirrors need independent readiness checks. Never block required
platform registries when introducing an allowlist.

## Upgrades and AutoNode

The modules no longer ignore explicit version or AutoNode changes. Review every
plan: a version edit can schedule an upgrade, and automatic OCM upgrades require
reconciling the configured target before another apply. HCP control-plane and
pool upgrades are separate operations; wait for the observed control-plane version
before updating pools. [Native upgrade guide](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.8/docs/guides/upgrading-hcp-cluster.md).

AutoNode enablement/role changes go through RHCS, which also performs post-create
activation. Disabling AutoNode is unsupported; retain its IAM configuration once
enabled. AWS IAM, discovery tags and Kubernetes NodePools remain separate owners
because RHCS does not provision those resources. See [AutoNode](AUTONODE.md).

## Verification

Run `TERRAFORM_BIN=terraform uv run scripts/check-rhcs-capabilities.py` after
initializing the HCP cluster module with committed locks. A provider upgrade must
review resource/field/type inventory changes, not silently regenerate approvals.
Run mock lifecycle, pool and AutoNode tests, both architecture roots in both
partitions, examples, security scans and live acceptance before release.
