# EFS shared application storage

Reviewed 2026-09-09. The layer uses the **Red Hat AWS EFS CSI Driver Operator**
from the `stable` catalog channel, not the upstream Helm chart or EKS add-on.
The maintained implementation moved to `openshift/csi-operator` for OpenShift
4.17 onward; the old standalone operator repository is obsolete for these
releases. See the [upstream migration notice](https://github.com/openshift/aws-efs-csi-driver-operator#readme).

## Supported release selection

The latest reviewed OpenShift operator line is 4.22. Existing 4.18–4.21 clusters
must consume their own compatible catalog bundles, not force-install a 4.22
operand. `stable` selects the eligible patched bundle; Manual InstallPlan
approval is the default. Review CSV version, approved images and upgrade path
before approval. Terraform waits for the cluster-matching CSV and driver
Available/not-Degraded conditions. Approve in a separate session within the
45-minute window, or re-run after approval. No moving upstream `latest` image or
hardcoded starting CSV is deployed. Pinned [source contracts](../gitops-layers/layers/efs-storage/release.yaml)
are API checks, not a guarantee of regional catalog availability.

All four roots expose the same configuration: commercial/GovCloud, Classic/HCP.
Confirm your ROSA release entitlement, regional EFS/AWS Backup support, catalog
and operand architecture before enabling. The module does not upgrade clusters
or establish support for every possible storage consumer. Follow the
[Red Hat EFS installation guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/using-container-storage-interface-csi#persistent-storage-csi-aws-efs).

## Deploy and secure

Use [efs-storage.tfvars](../examples/efs-storage.tfvars) as an overlay on a cluster
base. Supply the **actual worker security group IDs** in
`efs_config.allowed_security_group_ids`, including all relevant machine pools,
autoscaled and ARM workers. The default is empty and provisioning fails closed;
there is no VPC-CIDR fallback. Worker egress/NACLs must permit NFS to the mount
targets. Mount targets initiate no outbound connections, so their SG has no
egress rules. Stateful replies are still permitted.

Regional EFS stores data across AZs. Supply one private mount-target subnet per
worker AZ, all in the same VPC. Duplicate AZs are rejected. Preserve the existing
subnet ordering when upgrading: mount-target resource indices are unchanged.
The module checks VPC/AZ membership; operators must verify routing is private.
Private DNS and same-AZ mounts avoid preventable cross-AZ cost/latency. GovCloud
zero-egress also needs private EFS API/STS paths, applicable KMS connectivity,
DNS and mirrored operator/operand images. These layer settings do not build
every endpoint or mirror. Catalog source/namespace are configurable.

Encryption at rest is mandatory; infrastructure CMK is used when supplied.
Defaults are `generalPurpose` and `elastic`. Bursting is an explicit cost/workload
choice. MaxIO and incompletely configured provisioned throughput are rejected,
not silently changed. The filesystem has Terraform destruction protection.
See [AWS EFS performance guidance](https://docs.aws.amazon.com/efs/latest/ug/performance.html).

The operator receives the controller `ROLEARN` and manages its credentials via
CCO. Trust binds the exact OpenShift service accounts, issuer and `openshift`
token audience. No static AWS keys or node-instance-profile EFS permissions are
added. Access-point creation is scoped to this filesystem. Tag/delete rights
are scoped to the account/region and CSI-managed access points; post-create
tag reconciliation remains allowed because Red Hat propagates cluster tags.
The shared CSI tag is not a per-cluster isolation boundary: highly isolated
tenants should use separate AWS accounts/filesystems and separately reviewed IAM.

The established **regional** mount path uses TLS, access-point POSIX identity and
worker network isolation. It does not claim per-pod IAM authentication. The
filesystem policy denies plaintext, root access and mounts without access points;
its client allow is intentionally network/access-point based, not tied to the
controller provisioning role. Do not add `iam` to mount options using only that
role: node authentication is a separate design. One Zone/cross-account and node
`NODE_ROLEARN` workflows are not enabled by this layer. See
[AWS client authorization](https://docs.aws.amazon.com/efs/latest/ug/iam-access-control-nfs-efs.html)
and [access-point identity enforcement](https://docs.aws.amazon.com/efs/latest/ug/enforce-identity-access-points.html).

`efs-rwx-retain` is an explicit, **non-default**, RWX Filesystem class: TLS, Retain,
unique directories, non-root allocated POSIX IDs, directory mode 700 and no
access-point reuse. EFS enforces access-point identity rather than a pod's
`fsGroup`; any pod authorized to mount the same PVC can read its files. Namespace
RBAC, PVC admission and privileged-pod restrictions remain essential. Never use
`anyuid`, fixed root IDs or `chmod 777` as a workaround. PVC requested size is
binding metadata, not an enforced EFS capacity quota. See
[driver provisioning parameters](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/parameters.md).

## GitOps layers and consumers

| Consumer | Integration policy |
| --- | --- |
| Application shared files / reviewed AI datasets | Explicit EFS PVC; validate locking, latency and workload support |
| Prometheus / monitoring layer | Keep EBS block-backed storage; EFS class names are rejected |
| Loki | Keep S3 objects and the monitoring layer's block working volumes |
| Virtualization | Keep the supported NetApp VM disk/profile path; no EFS VM profile is created |
| OADP | No EFS CSI snapshots/data mover; use AWS Backup plus Kubernetes metadata protection |
| Argo CD / GitOps operator | No EFS requirement; do not force platform components onto shared NFS |

Prometheus explicitly excludes NFS/EFS for its local database. The name-based
Terraform guard cannot identify an external NFS class with an unrelated name;
verify the provisioner too. See [Prometheus storage requirements](https://prometheus.io/docs/prometheus/latest/storage/).

Terraform owns Subscription, driver and StorageClass. Workload Applications own
their namespace/PVC/workload declarations, not copies of these platform objects.
The exported filesystem ID waits for mount targets, policy and backup settings;
the role waits for its attached policy. Driver readiness precedes StorageClass
creation. For separate Argo Applications, gate workload sync on successful
platform apply and a real mount test: sync waves do not order Terraform or other
independent Applications. See [the acceptance example](../examples/efs/README.md).

## Backup, monitoring and recovery

Automatic EFS backups are enabled. AWS's default plan runs daily and retains
35 days; verify the regional plan, vault, IAM and completed jobs, and establish
approved RPO/RTO. Enabling the policy alone is not proof of a recovery point.
Budget for backup storage and retained access points/data. Cross-account copies,
Vault Lock and customized schedules/retention require a separate approved AWS
Backup design. See [AWS EFS backups](https://docs.aws.amazon.com/efs/latest/ug/awsbackup.html).

EFS CSI does not provide CSI volume snapshots; do not select EFS workloads for
the OADP layer's snapshot-data-mover policy and assume disk data is protected.
Back up Kubernetes metadata separately and preserve PVC/PV/access-point/path
mapping. OADP filesystem backup is a separately reviewed container-only option,
not the VM or default CSI path. Test restored files in isolation and reconstruct
access points/bindings deliberately; a filesystem recovery is not a whole-app
restore. See [EFS driver implementation](https://github.com/openshift/aws-efs-csi-driver).

Monitor CloudWatch EFS client connections, IO limits, throughput, burst credits
when applicable, storage cost, access-point quota and AWS Backup failures. Watch
operator conditions, Pending PVCs and FailedMount events. Per-volume metrics can
walk directories and add load; leave optional collection/tuning at operator
defaults until measured. Test two workers/AZs, pod replacement and isolated file
restore before production use.

## Existing-install migration

1. Preserve state and a tested recovery copy. Inventory PVC/PV handles, access
   points, POSIX IDs, root/static mounts and consuming worker SGs.
2. Review the plan: filesystem/KMS identity and mount-target ordering must remain
   unchanged. New encryption/performance settings can require replacement;
   destruction protection must not be bypassed to make an upgrade succeed.
3. Supply every legitimate worker SG before narrowing NFS. The new policy blocks
   plaintext, root and direct filesystem mounts. Migrate incompatible clients
   before applying; do not use a production outage to discover them.
4. The old Terraform credential resource is forgotten without deleting the live
   Secret. Verify operator/CCO takes ownership and refreshes usable credentials.
   The shared CSI namespace is not created/deleted by this layer. Reuse its
   existing all-namespaces OperatorGroup with `manage_operator_group = false`
   when owned elsewhere; do not install a second group or force field takeover.
5. The default class changes from `efs-sc` (Delete) to `efs-rwx-retain`. Old
   classes remain because manifests are apply-only. If you explicitly configured
   a legacy name, choose a new name: reclaim policy/parameters are immutable.
   Existing PVCs retain their class/PV policy; no automatic data copy or policy
   conversion occurs. Review PV retention separately before deleting claims.
6. Approve the compatible operator update, verify driver status, run mount/read
   acceptance and test AWS Backup restore before moving workloads. Decommission
   retained objects explicitly only after verifying no consumers/recovery needs.

Validation: `terraform -chdir=tests/efs test`, mocked AWS tests under
`modules/gitops-layers/efs-storage/tests`, and `uv run scripts/check-efs-contracts.py`.
These checks do not replace live catalog, AWS policy, NFS, SCC or recovery tests.
