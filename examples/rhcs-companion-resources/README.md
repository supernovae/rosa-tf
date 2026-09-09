# Compose native RHCS resources

This is a schema-checked composition example, not a complete deployment. Replace
the placeholder endpoints and use an existing cluster ID and approved provider
authentication. Applying creates the kubelet configuration and digest-mirror
policy; identity configuration is separately opt-in and puts its secret in state.

Use one owner per resource: do not also manage mirror policy through GitOps or
manage the same IdP with another Terraform state. Check cluster/region feature
availability. Built-in OAuth IdPs are not external-auth provider configuration.
Use references and explicit dependencies when composing in the same root.

The [capability inventory](../../docs/RHCS-CAPABILITIES.md) explains why identity,
emergency access, tuning and Day-2 log forwarders remain native companion
resources instead of adding a second generic wrapper around the provider API.
