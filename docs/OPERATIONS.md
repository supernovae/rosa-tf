# Safe operations

Use the [two-phase deployment guide](DEPLOYMENT.md). This 2.0 branch is a
development baseline and does not support applying over 1.x production state.

## Plans, state and credentials

Verify account, region, provider lock and endpoint identity before planning.
Review every replacement/deletion, IAM change and public endpoint. Apply the
reviewed saved plan; treat it and state as secrets. Do not post full plans,
bootstrap passwords or kubeconfigs in PRs. Use protected remote state with
locking, recovery/versioning and a separate access policy from workloads.

Use organizational SSO/short-lived credentials. Bootstrap administrators are
for initial access only; establish organizational RBAC and rotate/revoke access
under a tested recovery process. Never bypass CA verification to make a layer
apply, or force manifest ownership over a different manager.

## Updates

Platform operators are delivered by approved catalogs, not arbitrary upstream
images. Review InstallPlans and actual installed versions, image mirrors,
architecture and support before approval. Back up and test restore first for
stateful changes. Editing a protected creation-only/version field is not an
automatic upgrade procedure; use the reviewed ROSA upgrade workflow.

Keep Terraform platform ownership separate from workload Argo Applications.
Enable pruning only after reviewing object ownership and data retention.
Disabling a layer can remove some resources while retained objects remain;
read the layer guide and inspect the complete plan. Do not use skip flags as
a shortcut for dropping state or abandoning resources.

## Decommission

1. Confirm exact account/cluster ownership and obtain change approval. Preserve
   recovery copies, credentials, keys and workload definitions independently.
2. Stop workload writes, verify recoverability and review retained resources.
3. Remove cluster-facing layers while the API and authorized access still exist.
4. Disable `cluster_delete_protection` in a separate reviewed apply only when
   cluster deletion is intended. Do not bypass storage destruction safeguards.
5. Delete the cluster through its supported lifecycle and wait for confirmed
   completion. RHCS 1.7.8 includes a fix to keep deletion failures in state;
   do not hide provider errors or continue deleting IAM while uninstall is active.
6. Inspect residual resources and recovery/account dependencies before cleanup.

`scripts/vpc-cleanup.sh VPC_ID` is **read-only inventory**. Unattached does not
mean unowned or safe to delete. There is no VPC-wide orphan-deletion fallback,
automatic destroy-time shell cleanup or name-substring ownership inference.
Shared account IAM, BYO-VPC, KMS, retained S3/EFS/NetApp data need separate review.
Never remove state merely to make a failed destroy look successful.

## Recovery and acceptance

Use the [OADP](OADP.md), [EFS](EFS-STORAGE.md), [NetApp](NETAPP-STORAGE.md) and
[observability recovery](OBSERVABILITY-AWS-RECOVERY.md) guides. A completed backup
object is not proof of usable data. Test isolated restores, guest/application
consistency, KMS access and RPO/RTO. Retention is not the same as immutable backup.

Investigate failed catalog resolution, Pending PVCs, IAM denials and scheduling
events without relaxing security settings. Preserve redacted evidence and exact
installed versions for support; never claim schema-only tests certify deployment.
