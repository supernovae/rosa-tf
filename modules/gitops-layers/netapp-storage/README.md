# NetApp storage: FSx for ONTAP

This module provisions the FSx filesystem, SVM, bounded network access and backup/
performance settings. The native operator layer installs certified NetApp Trident,
verified REST backends and explicit container/VM storage policies.

Start with [deployment, security, performance and migration guidance](../../../docs/NETAPP-STORAGE.md).
The [example overlay](../../../examples/netappstorage.tfvars) applies to all four
ROSA environment roots after cluster provisioning.

## Interface

- Existing FSx capacity/generation/network inputs remain; Gen2 deployment types
  are now supported explicitly with generation-specific throughput validation.
- `netapp_fsx_config` controls approved client CIDRs/routes, backup/maintenance
  windows and optional provisioned IOPS.
- Supply separate sensitive `fsx_admin_password` and `fsx_svm_password`.
- `kms_key_arn` selects a customer-managed encryption key; otherwise FSx uses its
  AWS-managed default. Protect state and credentials independently.
- Outputs include filesystem/SVM IDs, management/NFS/iSCSI endpoints and resolved
  client CIDRs for the operator layer.

Trident uses direct SVM REST authentication. This module no longer creates an
unused CSI IAM role or accepts unused OIDC/account/role-path inputs. The previous
Trident role outputs are removed. Review consumers before upgrading.

FSx/SVM prevent-destroy guards intentionally block accidental replacement/deletion.
Allocate dedicated subnets explicitly and pass all client routes for Multi-AZ.
See the [full guide](../../../docs/NETAPP-STORAGE.md) for immutable class migration,
retention versus backup, credential rotation, node preparation and acceptance.

## Offline infrastructure tests

~~~sh
terraform init -backend=false -lockfile=readonly
terraform test
~~~

Tests use mocked AWS responses, not live FSx resources. Provider-free template tests
live in `tests/netapp`; `scripts/check-netapp-contracts.py` checks pinned certified
metadata, Go API field definitions and shared root/module contracts.

When updating the AWS provider lockfile, record checksums for both the Linux CI
runner and Apple Silicon development machines before committing:

~~~sh
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
~~~

Run this from this module's directory. Keep CI initialization read-only; do not
disable checksum verification to work around missing platform hashes. See
[Terraform's platform locking guidance](https://developer.hashicorp.com/terraform/cli/commands/providers/lock#specifying-target-platforms).
