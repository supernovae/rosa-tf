# OpenShift Virtualization layer

This directory is documentation, not a Terraform machine-pool module. Create
bare-metal pools through the environment root's `machine_pools` input. The shared
operator module owns the Subscription, HyperConverged instance and optional CDI
StorageProfiles; NetApp owns FSx, Trident, backends and storage/snapshot classes.

See the [deployment and operations guide](../../../docs/VIRTUALIZATION.md) and
[Classic configuration overlay](../../../examples/ocpvirtualization.tfvars).
The guide covers release compatibility, platform support confirmation, secure
installation, NetApp RWX disks, migration, images, monitoring and backup recovery.

Do not infer ROSA HCP or GovCloud support from the presence of shared Terraform
inputs. Verify the exact platform, region, release, hardware and storage with the
vendors before setting `virt_config.platform_support_confirmed=true`.
