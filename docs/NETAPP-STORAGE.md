# NetApp storage: Trident and FSx for ONTAP

Reviewed 2026-09-08. Applies to the commercial/GovCloud Classic and HCP roots.
Read the migration section before applying to an existing installation.

## Supported release and ownership

The certified package now contains **Trident 26.06.1**, using OLM package
`trident-operator`, channel `stable`, and initial CSV `trident-operator.v26.6.1`.
The bundle declares OpenShift 4.14–4.22 compatibility. Verify the running cluster's
own lifecycle, NetApp support entitlement and regional catalog availability.
[Certified bundle](https://github.com/redhat-openshift-ecosystem/certified-operators/tree/097b06e244849b605bc0f18f63edbcf83021afb8/operators/trident-operator/26.6.1),
[NetApp release](https://github.com/NetApp/trident/releases/tag/v26.06.1).

OLM approval defaults to **Manual**: stable is not a minor-pinned channel.
`startingCSV` selects the initial install; it neither upgrades an existing CSV nor
pins subsequent upgrades. Review each InstallPlan, its operator/operand images,
release notes and rollback limitations. Use one installation owner: do not layer
Helm, an EKS add-on or `tridentctl install` over OLM. Default operand images come
from the certified operator, including its digest-pinned related images.

Terraform owns FSx/SVM/network policy, the Subscription, TridentOrchestrator,
backends and StorageClasses. The operator owns CSI deployments, RBAC/SCCs and node
preparation. Workloads own PVCs, snapshots and VM definitions. Do not let the
restricted GitOps workload Application modify these platform objects. Adding
KubeVirt/CDI kinds to a workload AppProject is a separate reviewed permission change.

## Storage choices

| Class | Claim access / mode | Intended use |
| --- | --- | --- |
| `fsx-ontap-nfs-retain` | RWX / Filesystem | Shared container files, workspaces; also supported file-backed VM disks |
| `fsx-ontap-san-retain` | RWO (or supported RWOP) / Filesystem | ext4-backed container volumes, e.g. a database |
| `fsx-ontap-vm-rwx` | RWX / Block | Shared raw VM disks for live migration; no filesystem-format parameter |
| `fsx-ontap-snapshots-retain` | CSI VolumeSnapshotClass | Explicitly retained local snapshots |

The layer does not change the cluster's default StorageClass or default snapshot
class. All new PVCs should name their class explicitly. Classes select this layer's
labeled backends rather than any matching ONTAP backend. Shared FSx classes use
Immediate binding because they are not AZ-local disks; all eligible workers must
have storage access. Do not add topology restrictions that strand migration targets.

VM live migration needs shared storage, appropriate node capacity/networking, and
a supported OpenShift Virtualization deployment. RWX raw block is not a shared
POSIX filesystem: never mount the same disk read/write in independent guests or
containers without an appropriate clustered application. See
[NetApp VM protocol support](https://docs.netapp.com/us-en/trident/trident-get-started/requirements.html).
ROSA HCP with EC2 workers is not the same topology as HCP on KubeVirt guest VMs.
Storage support does not independently establish virtualization support for every
ROSA region, machine type or architecture.

The [PVC examples](../examples/netapp/nfs-pvc.yaml) and
[stopped VM example](../examples/netapp/vm-rwx.yaml) show explicit modes/classes.
The VM's disk is blank: add an approved OS import/installation before starting it.
The [virtualization layer](VIRTUALIZATION.md) optionally configures CDI StorageProfiles
when both layers are enabled, without changing storage defaults. Review and test
these policies before use. Do not delete existing golden images or
switch defaults just because an installation tutorial demonstrates that sequence.

## Credentials, TLS and permissions

Provide independent `TF_VAR_fsx_admin_password` and `TF_VAR_fsx_svm_password`
through a trusted secret-managed runner. The latter configures SVM vsadmin; the
filesystem administrator credential must not be reused for CSI. Both values can
enter Terraform state, so encrypt state/plan artifacts and restrict access.
Sensitive output marking is not encryption.

Prefer `netapp_storage_config.backend_secret_name` referencing a separately
managed Secret in `trident`. It can hold an SVM-scoped account or supported client
certificate credentials. Scope the ONTAP role to the operations required by the
selected drivers and validate it against
[NetApp's SAN preparation guidance](https://docs.netapp.com/us-en/trident/trident-use/ontap-san-prep.html).
Certificate authentication uses the documented `clientCertificate` and
`clientPrivateKey` Secret keys; test the actual role and certificate lifecycle.

With username/password authentication, Secret keys are `username` and `password`.
When `use_chap=true` (default for SAN), the same Secret must also supply
`chapUsername`, `chapInitiatorSecret`, `chapTargetUsername`, and
`chapTargetInitiatorSecret`. Provision valid bidirectional CHAP credentials and
matching target configuration; ordinary vsadmin credentials alone are insufficient.
Do not switch CHAP settings on an existing backend without NetApp's migration
procedure. CHAP authenticates iSCSI sessions; it does not encrypt data or establish
FIPS compliance.

The compatibility Secret created by Terraform now uses plaintext provider `data`
values, which the Kubernetes provider encodes once. The old code double-encoded
them. It cannot supply CHAP keys; SAN+CHAP requires the external Secret. Before
switching Secret ownership/names, deliver and verify the replacement; the old
Terraform-managed Secret is deleted when the external-secret option is enabled.
Never grant workload authors access to the Trident namespace or CSI credentials.

Both backends explicitly use ONTAP REST, not legacy ONTAPI/ZAPI. Configure a
certificate-matching `management_endpoint` and `trusted_ca_pem` from an approved
trust source. The layer base64-encodes the CA once. In this release an empty
trusted CA leaves REST server verification disabled, so an enabled layer rejects
an empty CA. This is verified in the
[release implementation](https://github.com/NetApp/trident/blob/v26.06.1/storage_drivers/ontap/api/ontap_rest.go).
Do not trust a certificate merely because an unverified endpoint presented it.

Direct SVM REST access does not need an AWS IAM role in the CSI pods. The old,
unwired role with wildcard FSx permissions, backup deletion and unnecessary KMS
grants is removed. AWS FSx/Secrets Manager integrations would require a separate
end-to-end identity design; adding an EKS annotation alone does not implement that
on ROSA. Terraform's AWS execution role still needs its infrastructure permissions.

## Worker preparation and safe failover

SAN requires either `netapp_operator_config.node_prep_iscsi=true` or an explicit
`nodes_prepared=true` assertion after validation. Automatic preparation is opt-in
because it can change node configuration and roll/reboot workers. Schedule the
change, respect disruption budgets, and test it first on representative workers.

Verify iSCSI initiators, active iscsid/multipathd, unique initiator identities, and
`find_multipaths no`. Every eligible node, including VM targets, replacement
workers and autoscaled pools, needs the same preparation. SAN backends omit
`dataLIF` so Trident can discover all target portals. Do not grant application pods
privileged SCCs to repair host configuration.
[Worker preparation](https://docs.netapp.com/us-en/trident/trident-use/worker-node-prep.html).

Force-detach defaults off. Enable it only with a tested fencing/non-graceful node
shutdown runbook that proves the old writer is stopped before a new writer starts.
An unavailable Kubernetes node is not proof that a VM or disk writer is powered off.
Keep operator defaults for CSI self-healing and component resources until metrics
justify tuning; do not scale the single controller deployment by hand.

## Network and GovCloud

Security groups permit TCP 443 (management), 2049 (NFSv4.1) and 3260 (iSCSI) from
worker subnet CIDRs by default. `netapp_fsx_config.client_cidrs` can provide reviewed
narrower/connected client networks. These ranges also filter node IPs used for
automatic exports; this filter is not itself an NFS export allowing every address.
Legacy UDP/portmapper ingress is removed. NFSv3, SMB, replication and external
management paths require a separate protocol/network design.
[AWS access controls](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/limit-access-security-groups.html).

Multi-AZ requires all client route tables for FSx floating endpoints and failover.
Generated VPCs pass their private tables; BYO-VPC users must supply
`netapp_fsx_config.client_route_table_ids`. Preserve FSx-managed routes and required
route-table tags. Dedicated subnets require explicitly allocated CIDRs; the old
hard-coded subnet arithmetic is removed. Check overlap, AZ diversity, free addresses
and endpoint address ranges before applying.
[AWS routing guidance](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/supported-fsx-clients.html).

Use approved private catalog/image mirrors and configure operator source,
image registry and pull-secret references. A custom Trident image alone does not
mirror the operator, sidecars or autosupport image. Mirror the certified CSV's full
related-image set and required architectures. Keep telemetry silenced unless
approved. FSx data access is private; zero internet egress still requires working
API, registry, DNS and storage routes. Do not introduce NAT to hide a missing mirror.

`netapp_enable_fips` is removed: it never mapped to a Trident setting and created
false assurance. Review actual OpenShift/ONTAP cryptographic modules, endpoint
policies, data-in-transit controls and accreditation requirements with your security
team. KMS at rest, TLS management and CHAP are distinct controls; plain NFS/iSCSI
is not made encrypted by any of them. Neither this layer nor GovCloud location
alone establishes FedRAMP authorization.

## Performance and cost

Keep the existing FSx generation during an operator upgrade. Second-generation
Single-AZ and Multi-AZ are now accepted explicitly; this layer configures one HA pair.
Changing generation is a storage migration, not a transparent operator upgrade.
Check [regional availability](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/available-aws-regions.html),
especially GovCloud East versus West, and account quotas.

| Deployment | Throughput MBps for the supported one-HA-pair configuration |
| --- | --- |
| SINGLE_AZ_1 / MULTI_AZ_1 | 128, 256, 512, 1024, 2048, 4096 |
| SINGLE_AZ_2 | 1536, 3072, 6144 |
| MULTI_AZ_2 | 384, 768, 1536, 3072, 6144 |

These values follow the current
[FSx API](https://docs.aws.amazon.com/fsx/latest/APIReference/API_CreateFileSystemOntapConfiguration.html).
The provider uses per-HA-pair throughput only for Gen2. Defaults remain Gen1/128
for compatibility/cost; use the explicit Gen2 example only for new approved systems.

Size from measured IOPS, block size, throughput, p95/p99 latency, queue depth and
working set—not a blanket “production=512 MBps” rule. Include VM boot storms,
concurrent imports/clones, backups, live migrations and failover. Benchmark only
disposable test volumes, using an approved tool/image, and compare application SLOs.
[AWS performance model](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/performance.html).

Use automatic SSD IOPS initially; `provisioned_iops` exposes explicit tuning with
a minimum of 3 per GiB and requires checking service maxima. Thin provisioning
requires capacity alerts and headroom. New backend defaults keep latency-sensitive
data on SSD (`tieringPolicy=none`); separate cold workloads before enabling tiering.
`qos_policy` references an existing reviewed ONTAP policy: prefer per-volume
non-shared limits to avoid a shared ceiling throttling unrelated tenants.
[Backend policy options](https://docs.netapp.com/us-en/trident/trident-use/trident-fsx-examples.html).

NFS uses hard v4.1 mounts. Default `nfs_nconnect=1` avoids unmeasured node-wide mount
changes; test 4/8 only where supported and measure the effect. Existing mounted
volumes do not automatically gain changed mount options. `0770` NAS permissions
and CSI `fsGroupPolicy=File` require an SCC-allowed workload group; test directory
ownership on an actual claim rather than granting 0777 or privileged application
access. Applications must coordinate concurrent writes.

Controller concurrency is GA for the selected drivers in this release but remains
an explicit opt-in. Enable it for a measured provisioning backlog; it accelerates
control operations, not the application's steady-state storage data path.
[NetApp scalability guidance](https://docs.netapp.com/us-en/trident/trident-use/controller-scalability.html).

Estimate provisioned SSD, throughput, extra IOPS, consumed backups/tiered storage
and applicable transfer charges. Thin volumes do **not** mean FSx SSD is billed
only for bytes written. Use the target region's
[AWS pricing calculator/rates](https://aws.amazon.com/fsx/netapp-ontap/pricing/);
do not extrapolate commercial prices or throughput availability to GovCloud.

## Snapshots, backup and acceptance

New classes retain PVs and snapshot content. Retention is not a backup or automatic
cleanup policy. CSI snapshots are on the same storage failure domain and are not
automatically application-consistent. Quiesce database/guest writes through a
supported workflow, test restore, and define an accountable cleanup owner.

Daily FSx backup retention defaults to seven days with explicit UTC windows.
Confirm each Trident-created volume actually has successful backups and restore
one into isolation. Use OADP or a separately reviewed Trident Protect deployment
for application metadata/data-movement requirements; do not assume a local snapshot
or the legacy Velero class label provides off-system recovery. Replication/cross-region
backup requires approved destinations, KMS policies, regional support and tested RPO/RTO.

Before production, record evidence of:

1. Approved CSV/version, TridentOrchestrator Installed, both backends Bound and
   last operation Success, and healthy CSI pods on every eligible worker.
2. Verified TLS and the expected SVM account; unauthorized clients/users denied.
3. NFS RWX writes from two approved nodes with correct permissions; container SAN
   attach/expand/restart; raw-block VM disk and live migration under representative load.
4. A controlled node/storage failover, multipath recovery, retained-claim behavior,
   snapshot restore and independent backup restore.
5. Capacity/IOPS/latency, provisioning and attach errors, CSI node health, snapshot/
   backup failures, credential/certificate expiry and alert delivery.

Use CloudWatch FSx metrics and supported Trident metrics with your
[observability stack](OBSERVABILITY.md). Review scraping auth/network access and
alert thresholds; do not expose storage credentials to dashboard users.

## Existing-install migration and retirement

Inventory/backup state, FSx/SVM IDs, backend UUIDs, Secrets, CSV, PVC/PV associations,
StorageClasses, snapshots and actual reclaim policies. Never combine an operator,
filesystem generation, credential, protocol and VM migration into one blind apply.

- Preserve FSx generation, endpoint identity and backend names. FSx/SVM and the
  Trident namespace have prevent-destroy guards; retained Kubernetes objects use
  apply-only. These guards are not a substitute for backups or careful state handling.
- The TridentOrchestrator is cluster-scoped; its invalid metadata namespace is
  removed. If Terraform proposes replacing the existing CR, stop and reconcile its
  recorded identity through a reviewed state/import procedure. Do not delete a
  working CSI installation just to resolve a namespace/state mismatch.
- Set `netapp_storage_config.legacy_classes_enabled=true` before the first upgrade
  if old classes are in use. Old names/immutable parameters are retained for migration
  only and still have Delete policies. Review the plan: leaving the flag false on
  an old installation can plan removal of those classes before retention is recorded.
- New retained class names avoid mutating immutable old StorageClass parameters.
  Existing PV policies and mounted options are unchanged. Move data by supported
  clone/restore/migration; a PVC's storageClassName is not an in-place migration.
- Install trusted certificates and external credentials first. Plan separate SVM
  password rotation, then verify backend operations. Remove the obsolete FIPS input.
- Verify the old CSI IAM role has no external consumers before its planned removal.
- Approve the 26.06.1 InstallPlan; verify actual operand version. Manual OLM approval,
  CRD registration, secret delivery and host preparation are staged operations.
  Fixed bootstrap delays can require a controlled retry; do not bypass failed checks.
- Retire old classes only after all claims and backups are accounted for. Removing
  the layer does not safely retire FSx data. Do not bypass prevent-destroy, remove
  CSI state, delete CRDs or forget state to make a storage-destroy plan succeed.

No live deployment is proven by repository tests. CI runs template tests, pinned
release field checks (CRDs preserve unknown fields), four-root input checks and
mocked FSx plans. Complete the above acceptance on your actual ROSA environment.
