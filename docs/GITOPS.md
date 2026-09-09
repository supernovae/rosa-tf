# Secure operation of the GitOps layer

Reviewed 2026-09-08. Applies to ROSA Classic and HCP in commercial and GovCloud
partitions. Read the migration checklist **before applying to an existing install**.
These defaults provide guardrails, not a claim that every deployment is secure
without account-specific configuration and operational tests.

## Releases and installation

| Running OpenShift | Selected operator channel | Notes |
| --- | --- | --- |
| 4.18–4.22 | `gitops-1.21` | Current compatible release stream; release notes list 1.21.4, issued September 3, 2026 |
| 4.14, 4.16, 4.17 | `gitops-1.20` | Compatibility fallback; verify the cluster's own lifecycle and entitlement |
| Other minors | Rejected | Update the verified matrix before use |

The [Red Hat lifecycle matrix](https://access.redhat.com/support/policy/updates/openshift_operators)
and [GitOps 1.21 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.21/html/release_notes/gitops-release-notes)
are the authority. A version-compatible operator does not revive an unsupported
OpenShift release. The regional catalog determines the actual patch. Confirm the
latest supported errata are mirrored before deployment in GovCloud; this repository
cannot prove your catalog/account availability. Use Red Hat operator-built operands,
not independently upgraded upstream Argo CD or Redis images.

Minor channels deliberately avoid an unreviewed minor upgrade through `latest`.
Automatic InstallPlan approval applies patches within that stream; choose Manual
when change governance requires it and provide a separate approval stage. Updating
The cluster modules forward explicit version changes to RHCS; verify the upgrade completes before changing layer streams.

New installs use `openshift-gitops-operator` with a dedicated OperatorGroup, as in
[Red Hat's installation guide](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.21/html/installing_gitops/installing-openshift-gitops).
Existing installations in `openshift-operators` must explicitly retain that
namespace until a planned OLM migration. Never run two subscriptions/operators
controlling the same Argo CD resources. The operand remains `openshift-gitops`.

## Two control planes, two owners

| Resource | Owner | Authorization |
| --- | --- | --- |
| AWS resources, platform operator Subscriptions, layer CRs | Terraform | Privileged infrastructure runner |
| ArgoCD CR, application namespace delegation, AppProjects, root Application | Terraform | Reviewed platform configuration |
| Allowed workload manifests inside the delegated namespace | Argo CD | Operator-generated namespace permissions plus AppProject restrictions |
| ROSA service-managed resources | Red Hat SRE | Do not take over with either tool |

Merely enabling GitOps no longer points Argo CD at this infrastructure repository.
Workload reconciliation requires `gitops_application.enabled=true` and an explicit
repository URL. The built-in `default` project is deny-all. The `workloads` project
permits one exact repo and one namespace, no cluster-scoped resources, and an
explicit workload kind list. RBAC, Secrets, Applications, AppProjects and operator
CRs are excluded by default. Namespace creation/delegation belongs to Terraform.

The old explicit Argo CD cluster-admin binding is removed. The ArgoCD CR also
disables the operator's default cluster-scoped grants. The Subscription explicitly
sets `ARGOCD_CLUSTER_CONFIG_NAMESPACES` to an empty string, so the operator scopes
the local-cluster cache to managed namespaces instead of watching the entire cluster.
`resource.respectRBAC=normal` skips resources the controller cannot list. This
operator-wide setting affects other instances too: inventory them before upgrading.
Do not add cluster-config namespaces back without a separate ownership/security design.
The namespace behavior was checked against the
[bundled operator implementation](https://github.com/argoproj-labs/argocd-operator/blob/758bac1d640a/controllers/argocd/secret.go)
and [Red Hat's operator settings](https://developers.redhat.com/articles/2023/03/06/5-global-environment-variables-provided-openshift-gitops).
Namespace delegation uses
the supported `argocd.argoproj.io/managed-by` label. The operator grants namespace
admin permissions there, so this is **not** a hardened boundary for mutually
hostile tenants: trust the namespace's code/authors and review any privileged
service accounts already present. Keep write access to `openshift-gitops` restricted
to platform administrators. AppProject policy is not a replacement for Kubernetes
RBAC, SCCs, NetworkPolicy or admission policy. See Red Hat's
[permission customization](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.21/html/declarative_cluster_configuration/customizing-permissions-by-creating-user-defined-cluster-roles-for-cluster-scoped-instances)
and [multitenancy guidance](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.21/html-single/multitenancy/index).

Do not use this Application as an unrestricted app-of-apps entry point. For more
teams/projects, define separate reviewed AppProjects and instance/RBAC boundaries.
Cluster configuration remains a privileged Terraform layer unless a distinct,
approved GitOps ownership migration is designed. Never have two reconcilers own
the same object or change generated Deployments instead of the operator CR.

## Bootstrap, TLS and credentials

Create the cluster first with `install_gitops=false`, then apply the GitOps overlay
with approved credentials from a runner that reaches the private API. The Kubernetes
providers verify TLS; optionally supply `gitops_cluster_ca_certificate` as PEM
from a trusted source. Null uses system trust. Do not restore `insecure=true` to
work around a trust error.

Prefer a short-lived token supplied through the secret manager/runner environment
as `TF_VAR_gitops_cluster_token`. Its lifetime must cover plan/apply; refresh before
an operation, not by writing credentials into committed tfvars. The dedicated
Terraform SA remains privileged because it installs operators, RBAC and layer CRs.
It must not be used by application pods; automatic token mounting is disabled.
After approved administrator authentication, an example TokenRequest is:

~~~sh
# Trusted runner only; disable command tracing/logging first.
export TF_VAR_gitops_cluster_token="$(oc -n rosa-terraform create token terraform-operator --duration=1h)"
# Run the reviewed plan/apply with both cluster and GitOps overlays.
unset TF_VAR_gitops_cluster_token
~~~

The issuer may cap token lifetime. Minting a privileged SA token requires tightly
controlled authorization and an audit trail. Do not mint it from an untrusted PR
job. Keep state/backups encrypted and access-controlled: sensitive marking hides
display, not state contents. See [Kubernetes service-account token guidance](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/).

The htpasswd/challenging-client OAuth path is a bootstrap fallback, not a general
HCP external-auth integration. It now requires jq, trusted HTTPS discovery (or an
explicit HTTPS issuer) and verified TLS. `CURL_CA_BUNDLE` can identify a trusted
PEM bundle for the API **and** OAuth endpoints. It does not inherit the Terraform
provider CA field. Authentication headers are supplied to curl on stdin, not in
process arguments; credentials/responses are not logged. No hostname guessing or
insecure fallback is used when discovery fails.

2.0 does not create permanent service-account token Secrets. Use short-lived
TokenRequest credentials from an independently authenticated trusted runner.
There is no supported in-place 1.x authentication migration; revoke old tokens
through a separately approved retirement workflow, never through the same
credential being revoked.

## SSO, access and availability

Local Argo CD admin is disabled, anonymous access and UI exec are disabled, and
unmapped authenticated users receive `role:no-access`. OpenShift OAuth via Dex is
the default. Set `gitops_instance_config.admin_groups` to approved identity-provider
groups; a Kubernetes cluster-admin binding alone does not guarantee the expected
group claim reaches Argo CD. Verify login before disabling any existing access path.

HCP external authentication may require direct OIDC instead of Dex OpenShift OAuth.
Set `gitops_instance_config.oidc_config` to the supported Argo CD OIDC configuration;
it replaces, rather than coexists with, Dex. Register the correct HTTPS callback,
issuer, client and groups claims. Reference credentials from a separately delivered
Secret (for example `$oidc-client-secret:clientSecret`), never literal secrets in
tfvars. The Secret needs the Argo CD labels and permissions documented for the
chosen version. `admin_enabled=true` is an explicit, temporary break-glass option:
protect, audit, test and disable it after SSO is restored. See
[Argo CD user management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/).

`gitops_application.view_groups` grants project application read access;
`sync_groups` adds sync, not application modification/deletion, override, repository
administration or exec. Trust deployers to deploy reviewed content and test the
effective RBAC with real user tokens, including an unauthorized user.

Development defaults to non-HA. Production overlays enable HA, two repo-server
replicas and two API-server replicas. Redis HA needs at least three eligible
nodes and suitable placement; check operator scheduling rules, resource requests,
AZ distribution, rollout disruption and capacity before enabling it. Controller
sharding serves multi-cluster scale; adding controller replicas does not inherently
parallelize a single destination. The public/private reachability of the reencrypt
Route follows your ingress setup: enabling TLS alone does not make it private.

## Repository trust, promotion and sync safety

Start with [the opt-in workload overlay](../examples/gitops-workloads.tfvars) and
[the harmless ConfigMap example](../examples/gitops-workload/kustomization.yaml).
Copy the sample directory to your own reviewed repository and point at its path.

~~~hcl
gitops_repo_url      = "https://git.example.mil/team/workloads.git"
gitops_repo_path     = "apps"
gitops_repo_revision = "main"
gitops_application = {
  enabled     = true
  namespace   = "team-a"
  view_groups = ["team-a-viewers"]
  sync_groups = ["team-a-deployers"]
}
~~~

Default sync is manual. Review rendered manifests and the diff, sync, and verify
health before promotion. For automation, set `automated=true` and use a reviewed
40-character commit SHA; pruning and self-heal remain separate opt-ins. Empty-app
auto-pruning stays disabled. `FailOnSharedResource=true` detects other Argo CD
owners, **not Terraform ownership**. `PruneLast=true` orders deletion after sync
health, but cannot make a destructive change safe. Do not enable force/replace
sync or skip missing-resource validation just to make a failed rollout green.
Use sync waves within one Application for genuine dependencies; waves do not
order Terraform resources or independently reconciled Applications.

Protect source branches, require reviews/CODEOWNERS and checks, use immutable
image digests and pin/vet Helm/Kustomize dependencies. Git commit pinning does not
authenticate the author: introduce supported signature verification and key
lifecycle controls if your provenance policy requires them. Do not install arbitrary
config-management plugins or give repo-server a cluster credential.

Deliver read-only repository credentials with short scope/rotation through an
approved secret system. Project-scope repository Secrets where supported; avoid
wildcard credential templates. Use the operator-supported trusted certificate and
SSH known-host configuration for private endpoints; never set repository insecure
flags. This root Application accepts HTTPS URLs without embedded credentials.
Do not let workloads manage the Argo CD credential namespace. See
[Argo CD declarative setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)
and [security guidance](https://argo-cd.readthedocs.io/en/stable/operator-manual/security/).

Prefer polling to an unnecessary inbound webhook. If enabling webhooks, use
supported secret references, verify signatures, limit ingress and rotate secrets.
Optional image updating must submit reviewed PRs to protected branches, not bypass
promotion. GitOps Agent hybrid mode and the new console resource pages are Technology
Preview in 1.21; they are not enabled by this layer.

## GovCloud, zero egress and network policy

Use `gitops_operator_config.source` / `source_namespace` for an approved mirrored
catalog. Mirror all operator/operand images and required architectures. Ensure
the repo-server can reach approved private Git/dependency endpoints, the server/Dex
can reach the approved IdP, and controllers can reach the cluster API. Retain DNS,
monitoring and operator-generated internal component flows. Audit the installed
NetworkPolicies before adding workload-specific restrictions; no generic deny-all
policy can safely infer your endpoint IPs and IdP routes.

Zero egress does not supply access to GitHub, public Helm repositories or external
SSO. Vendor/mirror remote bases and chart/image dependencies. Keep credentials,
backup data, notification destinations and Git within the approved boundary;
confirm service and architecture availability rather than assuming commercial
parity. Do not add NAT as a shortcut around a missing private dependency.

## Acceptance, monitoring and recovery

1. Check Subscription/CSV Succeeded and the ArgoCD CR Available status. Terraform
   waits for that CR status, but a fixed CRD-bootstrap delay is not an installation
   guarantee; Manual InstallPlans and slow catalogs require a deliberate retry.
2. Login as administrator, viewer, deployer and an unauthorized user. Verify the
   last user has no application access. Verify ordinary developers cannot modify
   AppProjects or Secrets in `openshift-gitops`.
3. Sync the harmless ConfigMap to the approved namespace. Attempt a different
   namespace, unapproved repository and cluster-scoped resource in nonproduction;
   confirm each is rejected. Check actual service-account permissions, for example:

~~~sh
oc auth can-i create deployments -n team-a --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
oc auth can-i create clusterrolebindings --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
~~~

The second must be denied. Investigate other existing grants if it is not. Also
verify the operator-generated `openshift-gitops-default-cluster-config` Secret's
`namespaces` field contains only the control namespace and explicitly delegated
namespaces; inspect that field only, not the entire Secret. Verify the controller
can list workloads in the delegated namespace and cannot list Secrets cluster-wide.

4. Observe diff/sync/health and metrics, deliberately cause a failed sync, and test
   the team's alert route. Monitoring is enabled on the ArgoCD CR; inspect generated
   ServiceMonitors and use the [observability guide](OBSERVABILITY.md). Track sync
   failures, prolonged OutOfSync/degraded apps, reconciliation latency, repo errors,
   certificate expiry and component resource pressure. Empty metrics are not health.
5. Rehearse Git revert/re-promotion, credential expiry and a node disruption. With
   automation enabled, pause it through the Terraform-owned Application before an
   emergency manual change; otherwise reconciliation can undo the intervention.

Back up Terraform state, desired CRs/AppProjects, application source, trusted CA/GPG
material and secret-manager recovery information with restricted access. Redis is
not the source of truth. Application data needs its own backup and tested restore.
Rebuild operators/instance from Terraform, restore external credentials/trust, verify
SSO and repository access, then review and sync workload revisions. Restore backups
in isolation first; include RPO/RTO and fresh sync/alert evidence in acceptance.

## Fix-forward adoption and retirement

2.0 is a fresh deployment baseline, not a supported in-place 1.x state upgrade.
Rebuild on separate state and restore approved workloads/data using tested recovery
procedures. Do not import obsolete permanent-token or count-switch behavior.

Keep API access available during deliberate teardown. Inspect finalizers and
external Applications before removal. Retained namespaces, policies and AWS data
require separate retirement decisions; state removal does not delete those
resources or revoke credentials. See [operations](OPERATIONS.md).
