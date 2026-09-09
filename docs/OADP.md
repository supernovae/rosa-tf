# OADP application and VM recovery

Reviewed 2026-09-09. This optional layer protects application resources and guest
VM disks/definitions, not EC2 hosts, the ROSA control plane or etcd. Shared inputs
across Classic/HCP and commercial/GovCloud do not certify every platform pairing.

## Supported releases and rollout

| OpenShift | OADP stream | Latest documented patch at review |
| --- | --- | --- |
| 4.19–4.21 | 1.5 | 1.5.7 |
| 4.22 | 1.6 | 1.6.1 |
| 4.18 | No current supported stream in this layer | Upgrade/support review required |

Red Hat's matrix and lifecycle determine the choice. OADP 1.4 maintenance ended
with 1.6 GA; documented EUS coverage is for 4.16, not 4.18. Unsupported minors
are rejected even in AWS-only mode. See the
[ROSA OADP support matrix and release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/backup_and_restore/oadp-application-backup-and-restore).

The Subscription uses the Red Hat `stable` channel and **Manual** approval.
OLM selects an eligible bundle; this code does not pin a starting CSV or promise
regional availability of a documented patch. Inspect the InstallPlan's version,
images and upgrade path before approval. Terraform waits up to 45 minutes for
the expected stream; approve separately or re-run after approval. Do not skip
required intermediate upgrades. The [release contract](../gitops-layers/layers/oadp/release.yaml)
pins maintained source revisions for schema tests, not released images.

Use [examples/oadp.tfvars](../examples/oadp.tfvars) over an approved cluster base.
Set `oadp_config.support_confirmed = true` only after checking cluster, region,
storage and VM support. The default creates no Schedule. Opt in with explicit
workload namespaces and `schedule_enabled = true`; keep `schedule_paused = true`
until restore acceptance. Wildcards and platform namespaces are rejected.
`oadp_backup_retention_days` sets Velero TTL, not S3 object expiration.

## Data path and credentials

EFS is not a CSI snapshot/data-mover target. Keep EFS workloads out of this
snapshot policy unless their data protection is separately handled; use the
[EFS AWS Backup and metadata-recovery guide](EFS-STORAGE.md). Filesystem backup
requires a separately reviewed container-only configuration and is not VM backup.

CSI snapshots stage disks; the built-in data mover copies them to Kopia in S3.
Metadata alone and an on-array snapshot are not independent recovery copies.
The DPA enables `openshift`, `aws`, `csi` and, for VM mode, `kubevirt` plugins.
It enables snapshot data movement and disables filesystem backup by default.
VM mode prohibits filesystem backup; container-only filesystem backup requires
explicit review of node access and workload exclusions. Preview incremental
QCOW2 and volume-group features are not enabled. See
[Red Hat VM backup support](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/backup-and-restore).

The Subscription supplies `ROLEARN`; OADP owns `cloud-credentials` with key
`credentials`. No static AWS keys are generated. Trust restricts issuer, two
OADP service accounts and token audience `openshift`. Object rights cover only
the existing `velero/` prefix, including Kopia subdirectories. Native EC2 snapshot
rights are absent: CSI infrastructure permissions belong to the driver.
Optional KMS permissions are key-scoped through regional S3. See the
[OADP STS implementation](https://github.com/openshift/oadp-operator/blob/c0da0daccd802c6c9ec7716723aeb613aef53fa6/pkg/credentials/stsflow/stsflow.go)
and [Velero repository prefix handling](https://github.com/vmware-tanzu/velero/blob/v1.16.2/pkg/repository/provider/unified_repo.go).

Before the **first** backup initializes a repository, provision a unique,
high-entropy `repository-password` in `openshift-adp/velero-repo-credentials`
through an approved secret manager; preserve an encrypted off-cluster copy.
For existing repositories, preserve the current password: changing it can make
backups unreadable and does not rotate existing encryption. Never commit or
print this Secret. See [Velero credential cautions](https://velero.io/docs/v1.16/file-system-backup/).

`backupImages: false` is deliberate. Protect approved registries/images separately;
restoring definitions cannot recover unavailable container disk images.

## Virtualization and NetApp integration

The Virtualization layer automatically enables the KubeVirt plugin and passes
its node tolerations. For an independently managed supported installation, set
`oadp_config.virtualization_enabled = true` and supply `node_agent_tolerations`.
Neither installs missing hypervisors nor establishes HCP/GovCloud VM support;
see [Virtualization prerequisites](VIRTUALIZATION.md).

With the NetApp layer, Terraform creates `fsx-ontap-oadp`: a Trident CSI
VolumeSnapshotClass labeled for Velero with `deletionPolicy: Delete`. This is
transient data-mover staging, separate from retained ordinary snapshots and the
Kubernetes default. Keep exactly one Velero-labeled class per CSI driver;
resolve existing labels first. For independently managed NetApp, supply an
equivalent reviewed class. See [Velero CSI lifecycle](https://velero.io/docs/v1.16/csi/)
and [NetApp configuration](NETAPP-STORAGE.md).

Verify snapshot/restore and data movement on actual VM storage, including RWX
Block volumes, tainted bare-metal nodes and available temporary capacity.
Node-agent readiness does not prove mover pods can mount disks. Back up VM,
DataVolume, disk, Secret and network dependencies together, not VM-only labels.
Install QEMU guest agents and test quiescing/application hooks; independent
disk snapshots are not inherently atomic application-consistent backups.

Follow the [VM acceptance examples](../examples/oadp/README.md). Restores request
halted guests and avoid overwriting existing objects. Isolate networking and
review MACs, identities and credentials before starting guests. Validate guest
checksums/transactions and measure RPO/RTO, not just Kubernetes status.

## Operations and disaster recovery

Before unpausing schedules, verify supported CSV, reconciled DPA, Available
BackupStorageLocation, Ready BackupRepository and completed disk DataUploads.
Investigate warnings/errors and missing volumes. Alert on missed backups,
age beyond RPO, failed transfers, maintenance errors, capacity and failed restores.

```sh
oc get csv,installplan -n openshift-adp
oc get dpa,backupstoragelocations,backuprepositories -n openshift-adp
oc get schedules,backups,restores,datauploads,datadownloads -n openshift-adp
oc get pods -n openshift-adp -o wide
```

S3 is encrypted, versioned, public-access blocked, owner-enforced and TLS-only.
CloudFormation retains the bucket; Terraform protects the stack from destruction.
Only incomplete multipart uploads expire. **Do not expire Kopia objects by age**:
old chunks may serve newer backups. Velero TTL and repository maintenance own
logical retention. Noncurrent versions remain and cost money; audit recovery
requirements before cleanup. Versioning is not immutable protection against
privileged compromise. See [AWS versioned expiration behavior](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html).

Replication and Object Lock are not configured here. Design approved recovery
copies separately, including KMS access, replication permissions, repository
consistency and retention compatible with Kopia maintenance. Do not add Object
Lock to the live repository without testing maintenance/deletion consequences.
Rehearse source-cluster loss: preserve bucket/prefix, password, encryption keys
and recovery IAM independently of state. A recovery DPA can mount the approved
source BackupStorageLocation read-only; this module creates its own bucket and
does not automate recovery-bucket adoption.

GovCloud zero-egress needs private S3/STS connectivity, DNS, applicable KMS paths,
mirrored operator/operand images and private CSI/FSx connectivity. Set catalog
source/namespace for the approved mirror. These inputs do not provision every
endpoint or prove image availability. Keep copies, secrets and keys inside the
approved boundary; see [FedRAMP guidance](FEDRAMP.md).

## Existing-install migration

1. Preserve state, bucket/prefix, repository password and a tested recovery copy.
   Inventory legacy native snapshots and required restore permissions.
2. Review OCP/OADP upgrade eligibility. 4.18 is blocked; do not force 1.6 on 4.21.
   Approve supported intermediate OLM upgrades as required.
3. Confirm unchanged bucket/DPA identities in the plan. The old Terraform
   credentials resource is forgotten with `destroy = false`, not deleted.
   Verify OADP reconciles the `credentials` key and trust before transferring data.
   Resolve ownership conflicts explicitly; forced field takeover is disabled.
4. Review removal of native EC2 snapshot permissions. Legacy recovery needs a
   separately reviewed policy; old backups are not automatically converted.
5. Resolve existing Velero-labeled Trident classes; preserve ordinary retained
   classes. Namespace and DPA cleanup are deliberately guarded.
6. Explicitly configure schedule/scope. The old implicit schedule is removed
   unless opted in. New backups are not owner-dependent on Schedule deletion.
7. Complete a fresh backup and isolated restore before unpausing production jobs.

## Validation

Run `terraform -chdir=tests/oadp test`,
`terraform -chdir=modules/gitops-layers/oadp init -backend=false -lockfile=readonly`,
`terraform -chdir=modules/gitops-layers/oadp test` and
`uv run scripts/check-oadp-contracts.py`. CI repeats schema, template and mocked
AWS tests. They do not replace live admission, IAM, CSI and VM recovery testing.
