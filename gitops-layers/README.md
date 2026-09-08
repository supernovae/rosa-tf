# GitOps and platform layers

The layer approach has two distinct owners: Terraform installs/configures platform
operators and their AWS dependencies; OpenShift GitOps reconciles explicitly
delegated application workloads. Enabling `install_gitops` alone does not deploy an
Application or let Argo CD manage the platform.

Start with [secure GitOps operation and migration](../docs/GITOPS.md). It covers
supported releases, Classic/HCP and commercial/GovCloud prerequisites, SSO/RBAC,
TLS and short-lived credentials, manual promotion, private repositories, monitoring,
backup, and an acceptance checklist. Review it before upgrading an existing install.

## Deployment

1. Provision a cluster using its environment's `cluster-*.tfvars` with GitOps off.
2. Verify private API access, CA trust and an approved runner identity.
3. Stack the matching `gitops-*.tfvars` for platform layers.
4. Optionally add [the workload overlay](../examples/gitops-workloads.tfvars),
   replacing the repository, path and identity groups. Sync is manual by default.

All four supported environment roots expose the same GitOps contract. New operator
installs use `openshift-gitops-operator`; existing global installs must explicitly
retain `openshift-operators` until an approved OLM migration. Production overlays
enable HA and require at least three schedulable workers.

## Platform layer guides

| Layer | Guide |
| --- | --- |
| GitOps operator, ArgoCD instance and workload boundary | [GitOps](../docs/GITOPS.md) |
| Monitoring, logging, dashboards and alerts | [Observability](../docs/OBSERVABILITY.md) |
| Certificate automation | [cert-manager](../modules/gitops-layers/certmanager/README.md) |
| Backup and restore | [OADP layer](layers/oadp/README.md) |
| Additional native layer resources | [Operator module](../modules/gitops-layers/operator/README.md) |

Layer YAML templates are rendered by Terraform, not directly installed by Argo CD.
Do not point the workload Application at this repository's platform-layer directory.
Keep secrets outside Git, and restrict state/plan artifacts as sensitive data.

For implementation and testing, see [the layer contributor guide](../docs/GITOPS-LAYERS-GUIDE.md).
