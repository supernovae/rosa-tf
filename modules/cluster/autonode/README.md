# AutoNode IAM

Creates the Karpenter controller role/policy and required control-plane-operator
permission. This module owns IAM only; the environment owns subnet discovery tags
after cluster creation, eliminating the previous optional duplicate tag owner.

Pass its `karpenter_role_arn` to the HCP module's `autonode_role_arn`. Native
RHCS activates and updates AutoNode. Do not remove these IAM resources while
AutoNode is enabled; disabling AutoNode is unsupported in RHCS 1.7.8.

See [the canonical AutoNode guide](../../../docs/AUTONODE.md),
[commercial HCP root](../../../environments/commercial-hcp/README.md) and
[example overlay](../../../examples/autonode.tfvars). No CLI activation step or
second Kubernetes controller is required.
