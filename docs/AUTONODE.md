# AutoNode / Red Hat build of Karpenter

The documented current path requires OpenShift **4.22+**. Confirm the target
region/account is eligible before enabling; provider support is not a universal
GovCloud availability guarantee. The packaged IAM/discovery/NodePool workflow
currently lives in the commercial HCP root, not Classic or GovCloud roots.

[Red Hat administration guide](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cluster_administration/managing-compute-nodes-using-red-hat-build-of-karpenter).

## Ownership and lifecycle

1. The AutoNode module creates controller IAM before the cluster.
2. Native RHCS `auto_node` activates the service after cluster readiness and
   handles later enablement/role changes. It is no longer lifecycle-ignored.
3. The environment alone manages subnet discovery tags after the cluster exists.
4. Phase two manages Kubernetes NodePools after CRDs and node classes are ready.

RHCS 1.7.8 does **not** support disabling AutoNode once enabled. Do not set
`enable_autonode=false` as an uninstall recipe or remove controller IAM while
nodes are running. Native cluster upgrades and Karpenter-managed node upgrades
have different lifecycles; complete required readiness/maintenance checks first.

## Safe examples

Use [the AutoNode overlay](../examples/autonode.tfvars) with a private base and
verified OpenShift version. NodePools default to on-demand capacity. Spot is
explicit and needs disruption-tolerant workloads, placement rules and tested
recovery. Review consolidation, expiry, budgets and capacity limits before applying.

Select exactly one `instance_type` or `instance_types`. Reserved-domain labels
are rejected rather than silently dropped. Use custom workload labels and matching
pod selectors/tolerations. No second upstream Karpenter controller is installed.

NodePools reference `karpenter.k8s.aws/EC2NodeClass`. For custom classes, configure
an `OpenshiftEC2NodeClass` using the current Red Hat schema; the platform manages
its corresponding EC2NodeClass. Do not manage that generated object independently.
Keep the default class untouched. Verify custom disk encryption, private subnets,
IMDSv2, KMS grants and the desired node version. RHCS has no NodePool/NodeClass
resource, so these remain Kubernetes configuration, not a missing RHCS wrapper.

## Acceptance

Confirm controller health, node-class/NodePool readiness, scheduling, private
network paths, interruption/drain behavior and alerts. Keep critical platform
capacity on demand. The native machine-pool Spot termination queue is not
interchangeable with Karpenter event handling. Clean up workloads and their pools
before retiring custom node classes; use a separately reviewed cluster retirement
procedure for final teardown.
