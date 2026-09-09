# 2.0 release readiness

2.0 is a fix-forward fresh-deployment release. Backward compatibility with 1.x
state is not a goal; maintain historical releases separately instead of adding
compatibility aliases, silent fallbacks or migration fixtures to new features.

Current status is recorded in [release-status.json](../release-status.json):
development, RHCS `1.7.8-prerelease.2`, release approval **false**. No 2.0 tag is
authorized. The workflow blocks tagging a prerelease provider even if GitHub's
API incorrectly marks its release as non-prerelease.

## Implemented preparation

- Four-root EFS/layer integration and explicit layer support boundaries.
- RHCS prerelease pin with Linux/macOS provider checksums.
- Native component routes: Classic console/downloads/OAuth; HCP console/downloads.
- Opt-in HCP Spot pools, reserved scheduling taint, on-demand base and IMDSv2.
- Deletion protection, explicit regional OpenShift version choice and private seeds.
- Removal of the no-op version check, unsupported HCP cluster-wide autoscaler
  controls, legacy bootstrap fixtures and automatic VPC orphan deletion.
- No permanent cluster-admin token creation, misleading Kubernetes destroy-bypass
  switch, obsolete HCP output aliases or deprecated AutoNode CLI output.
- No migration-only NetApp Delete-policy classes; retained classes are the baseline.
- Immutable CI Action references, enforced scans and a stable-release gate.

## Required before a 2.0 tag

1. RHCS 1.7.8 or a reviewed later stable version is published. Read its final
   changelog; compare installed schemas with this prerelease implementation.
2. Replace all exact RHCS constraints and cross-platform locks together. Remove
   development-only prerelease acknowledgment only after reviewing stable behavior.
3. Pass formatting, provider validation, fresh-bootstrap, network, pool, route,
   layer and repository contracts, plus security scans with reviewed exceptions.
4. Complete real deployment/teardown and recovery acceptance for all four target
   environments. Verify the actual support/catalog matrix; document exclusions
   instead of claiming universal support.
5. Validate private custom routes, certificate rotation and rollback. Test Spot
   interruption/drain behavior and retain on-demand critical services.
6. Review state handling, identity, account lifecycle, costs and backup/restore
   evidence. Set release status to ready and approval true in a reviewed PR.
7. Run the release workflow on reviewed main with the explicit target tag.

No timer or automatic dependency update may bypass this checklist. Native
resource presence in RHCS is not a promise that every region enables its API.

## Preparation verification

Local checks cover all four roots with no Terraform validation warnings, mocked
bootstrap/pool/route/network/storage behavior, layer templates and pinned release
schemas, example inputs, release/default safety guards, GitOps authentication,
ShellCheck and local documentation file links. The module Checkov scan passes
with the checked-in policy configuration; public-ingress and administrative-IAM
checks are no longer globally exempted.

Full hosted CI vulnerability/secret scans and real regional deployment, Spot
interruption, certificate rotation and restore acceptance are still required.
These local checks are not a production support or compliance certification.
