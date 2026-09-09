# NetApp workload acceptance examples

Install and verify the platform layer first; see [the guide](../../docs/NETAPP-STORAGE.md).
Use a disposable, approved namespace and replace workload-specific values. These
examples allocate real storage when applied; retained data needs explicit cleanup.

- `nfs-pvc.yaml`: shared filesystem claim; mount it from approved non-root
  workloads on two prepared nodes and verify SCC-allowed group ownership/writes.
- `container-san-pvc.yaml`: ext4-backed container storage; test attach, restart
  and expansion using a representative disposable application.
- `vm-rwx.yaml`: halted VM with a blank raw-block RWX disk. It is not a bootable
  OS image. Import/install your approved OS before testing live migration.
- `snapshot-and-restore.yaml`: local checkpoint and a separate restore claim.
  Quiesce the source, wait for snapshot readiness and verify restored data.

All resources are namespaced; select the same namespace for related claims and
snapshots. Do not apply the whole directory as an unreviewed production workload.
Raw RWX disks are not safe for independent concurrent writers. CSI snapshots do
not replace tested off-system/application-consistent backups.
