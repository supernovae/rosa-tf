# Native GitOps/platform operator module

This module uses `hashicorp/kubernetes` and `alekc/kubectl` to manage operator
Subscriptions, operator CRs and platform-layer resources. It is called by all four
environment roots after the cluster is provisioned. It does not create AWS resources;
the parent root wires storage, IAM and endpoints from the corresponding modules.

Read [secure operation and existing-install migration](../../../docs/GITOPS.md)
before applying. This is a privileged infrastructure module, not a general-purpose
untrusted workload runner.

## Contract and ownership

| Input | Behavior |
| --- | --- |
| `gitops_operator_config` | OLM namespace, approved catalog and Automatic/Manual approval |
| `gitops_instance_config` | HA, SSO groups, optional direct OIDC and opt-in break-glass admin |
| `gitops_application` | Explicit workload opt-in, delegated namespace, viewer/sync groups and sync controls |
| `gitops_repo_url/path/revision` | Explicit HTTPS workload source; automatic sync requires a commit SHA |
| `gitops_create_legacy_token` | Compatibility-only permanent cluster-admin token; false by default |
| `enable_layer_*` | Terraform-owned platform layers, independent of workload reconciliation |
| `skip_k8s_destroy` | Legacy resource-count switch; does not forget state or bypass API refresh |

The complete input schema is in [variables.tf](variables.tf) and
[gitops-variables.tf](gitops-variables.tf). Provider authentication is configured in
the parent environment; supply short-lived `gitops_cluster_token` credentials and
trusted `gitops_cluster_ca_certificate` PEM when system roots are insufficient.

## Security defaults

- Minor-pinned supported GitOps streams, operator-managed operand versions.
- SSO with explicit group mappings; no implicit viewer access or local admin.
- Re-encrypted route, verified provider TLS, annotation-based resource tracking.
- No cluster-config Argo CD instances; namespace-scoped cache and delegation.
- Deny-all default AppProject and an explicit repository/namespace/kind allowlist.
- Manual workload sync, pruning/self-heal off; no cascading Application finalizer.
- No implicit permanent Terraform ServiceAccount token; automount disabled.

Terraform retains ownership of the ArgoCD CR, AppProjects and root Application.
The operator owns generated deployments, RBAC and cluster credentials. Argo CD
owns only the permitted workload objects. Never patch generated operands or give
the workload controller Terraform's cluster-admin identity.

The namespace delegation grants namespace admin through the supported operator
label. AppProject restrictions do not make this safe for hostile tenants or
untrusted repository writers; keep the control namespace and workload authors trusted.

## Lifecycle and verification

The ArgoCD manifest waits for `status.phase=Available`. OLM bootstrap still has a
fixed initial delay, so a slow/mirrored catalog or Manual InstallPlan may require a
separate approval/retry. Offline validation cannot verify live OLM availability,
SSO claims, ROSA admission or repository connectivity.

GitOps/operator/workload namespaces and the deny-all default project use
`apply_only` to retain them during module removal. Review workload disposition
and retire these explicitly. Other resources remain Terraform-managed and may
be deleted when disabled. Never use `skip_k8s_destroy` as a state-removal command.

Use [the acceptance and migration checklist](../../../docs/GITOPS.md) and
[contributor tests](../../../docs/GITOPS-LAYERS-GUIDE.md). The
`terraform_sa_token` output is empty unless legacy token creation is enabled.
Console output directs users to SSO; the admin password command is provided only
when local admin was explicitly enabled.
