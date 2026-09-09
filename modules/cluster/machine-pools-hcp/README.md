# HCP machine pools

Native RHCS pools using exact `1.7.8-prerelease.2` during 2.0 development.
See [the canonical pool guide](../../../docs/MACHINE-POOLS.md) and
[Spot overlay](../../../examples/hcp-spot.tfvars) for current schemas.

Pools use IMDSv2 and on-demand capacity by default. Explicit Spot opt-in adds a
reserved NoSchedule taint and capacity label. Price limits are positive numbers;
Spot and its price are creation-only settings. Keep system, storage and VM
capacity on demand. Each HCP pool selects one subnet/AZ; unknown AZs fail closed.

Nested `autoscaling = { enabled = true, min = 0, max = 3 }` replaces fixed
replicas for autoscaled pools. HCP cluster-wide autoscaler tuning is unavailable
in this provider release and is not exposed. Unit tests mock all cloud providers.
