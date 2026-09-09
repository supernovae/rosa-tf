# Machine pools and capacity policy

The base cluster workers remain on demand. Additional pools are explicit in
`machine_pools`; there is no automatic move of critical services to cheaper
capacity. Confirm machine type, architecture, regional quota and AZ availability.
ARM worker support does not mean every operator/operand/workload image is ARM-ready.

## Autoscaling and versions

Use nested `autoscaling = { enabled = true, min = 0, max = 3 }` and omit
`replicas` when autoscaling. For fixed pools use `replicas`. HCP pool autoscaling
does not require cluster-wide autoscaler configuration; that RHCS endpoint is
still unavailable and its inputs/resource have been removed from this baseline.
Classic retains its supported cluster-wide autoscaler configuration.

HCP pools need an explicit available version no newer than the control plane and
within two minor versions behind it. There is no skip/no-op version-check flag.
Select a known AZ through `az_subnet_map` or an explicit subnet, not both.
An unknown AZ must not silently fall back to another subnet.

HCP pools also expose native capacity reservations (incompatible with Spot),
image type, per-pool repair, AWS tags, tuning/kubelet references and upgrade
acknowledgments. Check eligibility and create referenced configurations first.
See [capabilities](RHCS-CAPABILITIES.md) for single-owner native composition.

## HCP Spot — native stable provider

RHCS `1.7.8` adds numeric `aws_node_pool.max_spot_price` and
`use_spot_instances`. See the [exact provider schema](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.8/docs/resources/hcp_machine_pool.md).
Use [hcp-spot.tfvars](../examples/hcp-spot.tfvars) only after regional/API support
confirmation. Omit a price for the provider's on-demand price cap; supplied prices
must be positive and Spot must be enabled. Capacity choices are creation-only;
do not treat changing an existing pool to Spot as an in-place migration.

The module adds `rosa-tf.io/capacity-type=spot` and the NoSchedule taint
`rosa-tf.io/spot=true`. Only interruption-tolerant workloads should select and
tolerate it. Do not place the only replicas of GitOps, monitoring, storage
controllers, databases or VM infrastructure there. Keep on-demand fallback,
topology spreading, sufficient replica counts and tested checkpoint/retry logic.
PDBs and drain grace periods do not prevent involuntary Spot interruption.

HCP worker pools require IMDSv2. The optional `node_drain_grace_period` is whole
minutes (0–10080), not an extension of an EC2 interruption notice. Additional
worker SGs and disk size must be selected before creation. The current interface
does not combine Spot with capacity reservations.

Classic Spot keeps its native `rhcs_machine_pool` path. Do not copy HCP provider
field nesting directly into Classic resources. Both require region/capacity and
workload interruption review, not a claimed fixed percentage cost saving.

## Storage and operations

For EFS, include every consuming pool's worker SG in the approved list. For
NetApp/VMs, perform node preparation and storage/snapshot acceptance before
scheduling workloads. Validate node-agent/data-mover coverage on tainted nodes.
Use on-demand supported bare metal for the Virtualization examples.

Monitor pending pods, scale-up errors, unavailable capacity, drain duration,
interruption recovery and costs. Benchmark comparable ARM/x86 workloads; neither
ARM nor Spot is automatically the cheapest choice for every workload.
