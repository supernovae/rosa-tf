# OADP layer

See the [deployment and migration guide](../../../docs/OADP.md) and
[VM acceptance examples](../../../examples/oadp/README.md).

Terraform renders regional STS/S3 configuration. Standalone YAML files contain
reference placeholders, not a ready-to-apply overlay. Do not let Argo CD and
Terraform own the same platform resources.

The stable channel selects OADP 1.5 for OpenShift 4.19–4.21 or 1.6 for 4.22.
Manual approval, support confirmation and explicit workload scope are required.
Schedules are opt-in and initially paused. CSI data movement protects VM disks
in S3; enabling the VM layer automatically adds KubeVirt integration.

OADP owns STS credentials. Obsolete credential manifests were removed; migration
forgets their Terraform resource without deleting the live Secret. Velero TTL
controls retention, never object-age expiration of Kopia chunks.
