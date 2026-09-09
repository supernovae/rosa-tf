# AutoNode NodePools

Creates Kubernetes NodePools after native RHCS AutoNode enablement and CRD/node
class readiness. RHCS has no NodePool or custom NodeClass resource.

The canonical input schema is in [variables.tf](variables.tf). NodePools default
to on-demand capacity, use exactly one instance-type selector, and reject reserved
label domains instead of dropping user input. Use the managed EC2NodeClass as the
reference target; do not force field ownership or replace the managed controller.

See [AutoNode](../../../docs/AUTONODE.md) and
[the scoped example](../../../examples/autonode.tfvars) for readiness, lifecycle,
custom-class boundaries and interruption safety. Mock tests do not prove that a
particular regional service accepts a NodePool or provisions capacity.
