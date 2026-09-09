# ROSA HCP cluster module

Native `rhcs_cluster_rosa_hcp` lifecycle for the four-root framework. Use the
[HCP environment](../../../environments/commercial-hcp/README.md) and
[deployment guide](../../../docs/DEPLOYMENT.md) rather than an incomplete standalone module recipe.

The 2.0 development baseline is Terraform >=1.16.1,<2.0 with exact RHCS
`1.7.8`. Deletion protection defaults on, instance metadata requires
IMDSv2, and native creation-only bootstrap credentials remain sensitive in state.

`current_version` reports the deployed control-plane version. Native RHCS manages explicit
version changes; inspect scheduled upgrades and required acknowledgments.
Perform supported ROSA control-plane upgrades first, refresh, then review pool
upgrades against the observed version. There is no bypass for the root pool
version guard and no unsupported cluster-wide HCP autoscaler input.

See [machine pools](../../../docs/MACHINE-POOLS.md) for per-pool scaling, Spot,
placement and interruption safety. This module does not prove regional capacity,
zero-egress eligibility or operator support.
