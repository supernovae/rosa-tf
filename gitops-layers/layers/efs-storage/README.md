# EFS CSI layer

Use the [EFS deployment and migration guide](../../../docs/EFS-STORAGE.md).
Terraform renders these templates; they are not a standalone Argo Application.
The supported Red Hat stable operator owns operands/CCO credentials. Manual
approval and readiness checks precede the non-default retained TLS StorageClass.
Never install another EFS Helm driver alongside the operator.
