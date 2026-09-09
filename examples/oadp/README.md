# VM backup and restore acceptance

Read [the OADP guide](../../docs/OADP.md) before applying anything. These examples
operate on guest VMs, their Kubernetes definitions and persistent disks—not
EC2 hosts, ROSA control planes or etcd.

1. Prepare a supported OADP/Virtualization/CSI environment and approved workload
   project. For NetApp use the [VM disk pattern](../netapp/vm-rwx.yaml), but install
   an approved OS and write/check test data first: that fixture is halted/blank.
2. Verify the repository is Available and CSI snapshot/restore works. Protect all
   VM dependencies in the workload namespace; do not use a VM-only label selector
   that accidentally omits Secrets, DataVolumes or related resources.
3. Apply [backup-vms.yaml](backup-vms.yaml). Wait for Completed **and** inspect
   errors, warnings, DataUploads and repository health. A completed metadata
   backup alone is not proof that disk bytes reached S3.
4. Prepare an isolated restore destination and network policy before applying
   [restore-vms.yaml](restore-vms.yaml). The supported KubeVirt restore label
   requests Halted guests; verify the restored VM's runStrategy and disk readiness.
5. Review network attachments, identities/MACs, credentials and guest consistency.
   Start only after authorization; compare guest checksums and application data.
   Measure elapsed recovery time and data loss against your RPO/RTO.
6. Only then unpause the explicit schedule in your Terraform configuration.

Use unique Backup/Restore names per test. No example deletes production data,
starts restored VMs, overwrites existing resources or creates a public endpoint.
Namespaces are not a substitute for a separately isolated disaster-recovery
cluster; network-attached guests and cloned identities need explicit review.
