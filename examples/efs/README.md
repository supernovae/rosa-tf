# EFS acceptance and workload GitOps

Read [the deployment/migration guide](../../docs/EFS-STORAGE.md) first. Create an
approved `efs-acceptance` project and provision the Terraform-owned layer before
syncing [pvc.yaml](pvc.yaml) through an authorized workload Application.

Use two non-root pods from your approved image mirror, with restricted SCC,
no privileged/host access, no added capabilities and no service-account token
mount. Mount `shared-files` at `/data` in both pods and schedule them on different
eligible workers/AZs. Write a unique test marker in one, read/verify it from the
other, then replace a pod and verify persistence. Do not use production data.
EFS replaces client IDs with the access-point identity; do not request anyuid or
chmod 777 to make shared files work.

Verify the PV has driver `efs.csi.aws.com`, TLS mount options and Retain policy;
verify its access point has a unique path and non-root POSIX identity. Test that
unapproved workers cannot mount and that operator/driver pods reconcile cleanly.
PVC Bound alone does not prove mounting, encrypted transport or usable files.

The PVC annotations prevent ordinary Argo pruning/deletion; they are not a
substitute for RBAC and backups. Keep platform resources out of the workload
Application. Sync waves order resources within an Application, not Terraform
and independent Applications. Gate workload sync on completed platform apply
and live mount acceptance. Review manual PVC deletion and retained-volume
cleanup separately; these examples do not delete data.

Confirm a successful AWS Backup job and perform an isolated file restore.
Record the mapping from namespace/PVC/PV to filesystem/access point/path and
verify restored contents/checksums. An AWS filesystem backup does not restore
Kubernetes declarations, access-point bindings or the complete application by
itself. Keep approved definitions in Git and secrets in a recovery-capable vault.
