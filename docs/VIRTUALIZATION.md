# OpenShift Virtualization with NetApp storage

Reviewed 2026-09-09. This layer installs Red Hat's supported HCO operator stack,
not standalone community KubeVirt/CDI operators. HCO owns its operands; Terraform
owns the Subscription, HyperConverged configuration and optional storage profiles.
Do not edit generated KubeVirt/CDI objects or give Argo CD concurrent ownership.

## Release and platform decisions

Use the `stable` channel in the **target cluster's** Red Hat catalog. It selects
the compatible OpenShift Virtualization stream; the globally newest release is
not necessarily installable on an older ROSA cluster. Current upstream product
documentation covers 4.22. This change does not upgrade OpenShift or pin a 4.22
CSV onto the repository's 4.18 GovCloud clusters. Verify regional ROSA versions,
catalog channel head, support lifecycle/EUS entitlement and upgrade path.

Automatic InstallPlan approval remains the Red Hat recommendation/default.
Use `virt_config.install_plan_approval="Manual"` only with staffed review and
patching procedures. Approve the InstallPlan during Terraform's 45-minute wait,
or rerun after approval; no timeout is an authorization to force installation.
Private catalogs can be supplied using `catalog_source`/`catalog_namespace`.
See [Red Hat installation guidance](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/installing)
and [release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/release-notes).

| Environment | Deployment position |
| --- | --- |
| Commercial Classic | Documented ROSA Classic path; verify bare-metal instance and storage support |
| GovCloud Classic | Same code, but confirm regional operator/hardware/FSx support and authorization boundary |
| Commercial/GovCloud HCP | Shared inputs are not certification; obtain explicit Red Hat confirmation for the exact topology before enabling |
| ARM VM workers | Not the default migration example; verify guest and platform restrictions separately |

The current OCP guide explicitly names ROSA Classic. Do not confuse ROSA HCP
running EC2 workers with hosted clusters running **on** OpenShift Virtualization.
Set `virt_config.platform_support_confirmed=true` only after this review. The
flag is an operator assertion, not an automated support check or an override of
vendor support terms. See [ROSA virtualization requirements](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/virtualization/installing).

## Deployment sequence

1. Select an approved Classic base configuration and merge the worker pools from
   [the overlay](../examples/ocpvirtualization.tfvars). It is not a complete cluster
   file. Preserve existing pools; Terraform lists/objects are replaced, not deep
   merged across tfvars files. Provision the cluster and pools first with
   `install_gitops=false`. Keep the API private and provide private runner access.
2. Check bare-metal quotas, available instance types/AZs, KVM CPU capabilities,
   matching CPU features, and N+1 capacity. Three workers are an example, not a
   guarantee of HA. Do not autoscale a VM pool to zero.
3. Configure [NetApp](NETAPP-STORAGE.md): FSx routing, bounded worker CIDRs,
   trusted CA/hostname, independent filesystem/SVM credentials, backend Secrets,
   SAN enablement and reviewed iSCSI preparation. Verify CSI agents run on the
   **tainted virtualization workers**, including multipath and reboot readiness.
   Enabling node preparation may roll workers; use a maintenance window.
4. Apply the layer phase. Confirm support explicitly. OLM installedCSV and HCO
   Available=True/Degraded=False/Progressing=False are deployment gates.
   HCO infra components use their own placement settings; they do not need
   expensive bare-metal VM nodes by default.
5. Verify backend Bound status and provision test claims before creating VMs.
   Test clone, snapshot, restore, expansion and cross-worker access on the actual
   FSx deployment. No offline test establishes data-path health.

```sh
oc get packagemanifest kubevirt-hyperconverged -n openshift-marketplace -o yaml
oc get subscription,installplan,csv -n openshift-cnv
oc wait hyperconverged/kubevirt-hyperconverged -n openshift-cnv --for=condition=Available --timeout=45m
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv -o yaml
oc get nodes -l node-role.kubernetes.io/virtualization -o wide
oc get tridentbackendconfigs -n trident
oc get storageclass fsx-ontap-vm-rwx fsx-ontap-nfs-retain
oc get storageprofile fsx-ontap-vm-rwx fsx-ontap-nfs-retain -o yaml
oc get volumesnapshotclass fsx-ontap-snapshots-retain
```

## NetApp interoperability

When both layers and `virt_config.netapp_storage_profiles` are enabled (default),
the virtualization layer manages these CDI profiles **after** HCO and the NetApp
classes are ready:

| Storage class | Claim mode | Intended use |
| --- | --- | --- |
| fsx-ontap-vm-rwx | ReadWriteMany / Block | Preferred SAN VM disk pattern; only created when SAN is enabled |
| fsx-ontap-nfs-retain | ReadWriteMany / Filesystem | Shared NFS VM/container storage alternative |

Both use explicit `csi-clone` and name `fsx-ontap-snapshots-retain` for CDI snapshot
cloning when that strategy is used. CDI can fall back to a copy when cloning
constraints are not met; check actual status and events. This is not a promise
of cross-SVM or cross-cluster instant clones. Profiles do not mark either class
as cluster-default or virt-default and do not migrate existing disks.

RWX **raw block** allows source/target virt-launcher access during migration; it
does not make a guest filesystem safe for simultaneous independent writers.
Never attach the same ordinary filesystem read/write to unrelated VMs.
VM snapshots choose CSI snapshot classes through KubeVirt's selection logic,
not solely CDI's profile. If legacy/default classes coexist, verify the actual
VolumeSnapshotClass used and its retention policy; do not silently change it.

Sources: [NetApp protocol requirements](https://docs.netapp.com/us-en/trident/trident-get-started/requirements.html),
[NetApp ROSA storage setup](https://docs.netapp.com/us-en/netapp-solutions-virtualization/openshift/osv-trident-install.html),
[Red Hat storage profiles and boot sources](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/storage).

## VM images, placement and migration

Automatic common boot-image imports are off initially to avoid uncontrolled
external downloads and storage consumption. Supply approved, patched internal
golden images and their trust/pull-secret configuration; then deliberately
enable `common_boot_images` if those imports are permitted. For 4.19+ the layer
uses `spec.enableCommonBootImageImport`; older HCO uses the compatibility feature
gate. Obsolete Tekton and host-passthrough gates are not emitted.
See the [4.19 API migration notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html-multi/virtualization/about).

Use the console's **Virtualization** perspective to create a project, review
Overview health, and create a VM using an approved boot source, instance type
and OS preference. Select the NetApp class explicitly. Size vCPU/memory from
measurements; the layer no longer overrides HCO migration timeouts/concurrency
or CPU allocation defaults. CPU overcommit is workload-specific, not free
capacity. Use supported common CPU models for heterogeneous migration pools;
host-passthrough is not a universal performance best practice.

[The stopped NetApp VM](../examples/netapp/vm-rwx.yaml) is a storage acceptance
fixture with a blank disk, not a bootable OS. It now includes the selector and
NoSchedule toleration for the example pool. Install/import an approved OS and
guest agent before starting it; an empty disk cannot establish guest readiness.

For live migration, verify the VMI reports LiveMigratable, all writable disks
and network bindings support migration, and the destination has sufficient
capacity and compatible CPU features. RWX alone is insufficient. Prefer the
default pod network with masquerade for the initial test; use reviewed
OVN/Multus secondary networking only when necessary and supported by ROSA.
Do not enable post-copy, GPU passthrough or preview gates just to bypass
migration failures. GPU passthrough does not require the OpenShift AI layer.

```sh
oc get vmi -n vm-workloads -o wide
oc get vmi storage-acceptance-vm -n vm-workloads -o yaml
virtctl migrate storage-acceptance-vm -n vm-workloads
oc get virtualmachineinstancemigrations -n vm-workloads
```

Test a planned worker drain with spare capacity before production, then validate
storage failover and guest I/O integrity. ARM ROSA has specific live-migration
restrictions; do not apply the AMD64 LiveMigrate example to ARM or infer guest
portability across architectures. See [ROSA live migration](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/virtualization/live-migration).

## Security, observability and recovery

Delegate project-scoped VM permissions through groups, not cluster-admin.
Restrict console, serial/VNC and SSH access; use approved Secrets and guest key
injection rather than passwords in Git. Review cross-namespace image clone
permissions. Do not grant tenants privileged SCCs or hostPath access as a fix
for storage failures. Keep migration traffic private; do not disable its TLS.
FSx encryption does not automatically encrypt guest traffic or establish FIPS
compliance. Guest patching/licensing remains the workload owner's responsibility.
From 4.19, VM migration requires explicit `kubevirt.io:migrate` permissions;
bind that role only in the authorized project, rather than cluster-wide.

The openshift-cnv namespace participates in cluster monitoring. Use the
Virtualization Overview, VM details and Observe alerts for VM/node health,
storage latency, capacity and migration errors. Test alert routing to the
on-call team. Review CDI import/clone events and storage-profile status if a
disk stays Pending. The optional [observability layer](OBSERVABILITY.md) adds
retention and team workflows; it is not required for HCO's built-in metrics.

Retained CSI snapshots and FSx automatic backups are useful but are **not** a
complete VM disaster-recovery plan. Protect VM/DataVolume definitions, Secrets
and disks together using a supported OADP/CSI data-mover or Trident Protect
design. Enable the optional [OADP layer](OADP.md) for integrated KubeVirt plugins,
NetApp CSI data movement and halted-VM restore examples. Virtualization alone
does not install backup protection. Check the OADP support gate before enabling it.
Use guest-agent quiescing/application hooks for application consistency.
Keep encrypted recovery copies in approved AWS accounts/regions, test KMS/S3
permissions and Object Lock/retention where appropriate, and measure restored
guest RPO/RTO. Do not assume FSx snapshots alone protect against account loss.
See [Red Hat VM backup/restore](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/virtualization/backup-and-restore)
and [NetApp VM protection](https://docs.netapp.com/us-en/netapp-solutions-virtualization/openshift/osv-vm-dp-using-tp.html).

## Existing-install migration and validation

- Back up state and VM data first. Keep resource names and namespace identity.
- Plan the infrastructure placement change: controllers can move away from
  bare-metal nodes. Ensure eligible untainted worker capacity or configure
  `virt_config.infra_node_selector` and `infra_tolerations`.
- Review boot-source changes before apply. Disabling imports removes managed
  import schedules; do not delete golden-image PVCs to make reconciliation pass.
- Removing explicit CPU/migration overrides restores operator policy; review
  existing custom tuning and running guests before scheduling maintenance.
- Resolve field ownership conflicts explicitly; force-conflicts is now off.
  Do not force-adopt CDI profiles already owned by another platform manager.
- Read the NetApp migration guide before switching legacy classes. Existing
  disks are not moved automatically; use an approved disk/VM migration workflow.
- Namespace destruction is blocked; HCO and profiles are retained on removal.
  There is no Kubernetes destroy-bypass switch. Uninstall requires a
  separately reviewed workflow after workload backup and evacuation.

Offline checks: `terraform -chdir=tests/virtualization test` and
`uv run scripts/check-virtualization-contracts.py`. The checker uses pinned
upstream HCO schemas and vendored CDI API definitions; it does not certify a
downstream release or evaluate admission CEL rules. Run live server-side
dry-runs, inspect installed CRDs and perform the acceptance tests above on
each approved target environment before production.
