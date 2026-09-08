# Developing and validating platform layers

For installation, security, support streams and operations, use [GitOps](GITOPS.md).
This guide describes the repository implementation, not a second installation path.

## Ownership and data flow

Environment inputs → AWS dependency modules → native operator module → operator CRs.
Terraform owns those resources and the workload AppProject/Application boundary.
Argo CD reconciles only approved manifests in an explicitly delegated namespace.

Do not introduce shell-based installers, a second Helm/operator owner, or an
app-of-apps that re-applies Terraform-owned platform resources. Operator-generated
Deployments, RBAC and Secrets must be configured through supported CR fields.

## Adding or changing a layer

1. Verify Red Hat support against the actual OpenShift minor and AWS partition.
   Check architecture support, private endpoints, mirrored dependencies and product
   lifecycle separately. Do not substitute an upstream image for a supported operand.
2. Add typed inputs with safe defaults and plan-time validation. Wire them through
   all four roots and the native operator module; preserve compatibility explicitly.
3. Render YAML through `templatefile` and `yamlencode`. Specify the supported
   apiVersion, ownership, namespace and actual readiness where available.
4. Keep cloud dependencies in their AWS modules and pass outputs to the operator
   module. Do not hard-code partition ARNs, region endpoints or account IDs.
5. Decide deletion behavior and migration before changing resource addresses or
   defaults. Retention is different from state removal. Document replacement,
   permission changes and independent credentials needed during rotation/teardown.
6. Add provider-free template tests, release-schema checks, input contract checks,
   updated examples and a live nonproduction acceptance procedure.

## GitOps implementation map

| Concern | Source |
| --- | --- |
| Supported minor channels | `gitops-layers/layers/gitops/channels.yaml` |
| Subscription, ArgoCD, AppProject, Application | `gitops-layers/layers/gitops/*.yaml.tftpl` |
| Native resources, delegation and readiness | `modules/gitops-layers/operator/gitops-core.tf` |
| Shared typed contract | `gitops-variables.tf` in operator, four roots and tests |
| Bootstrap authentication | `modules/utility/cluster-auth/get-token.sh` |
| Behavior/security regression | `tests/gitops/` |
| Strict pinned release schemas and contract parity | `scripts/check-gitops-schemas.py` |

Changing the channel matrix requires checking Red Hat's lifecycle table and release
notes, updating the pinned schema sources and testing every retained compatibility
stream. Catalog patches can differ by account/region/mirror; schema compatibility
does not prove deployment availability.

## Local validation

Use the Terraform version pinned by `.terraform-version`, from the repository root:

~~~sh
terraform -chdir=tests/gitops test
python3 -m unittest discover -s tests/gitops -p 'test_*.py'
uv run scripts/check-gitops-schemas.py
uv run scripts/check-examples.py
shellcheck modules/utility/cluster-auth/get-token.sh tests/gitops/curl-fixture.sh
~~~

The schema checker can use `TERRAFORM_BIN` for a version-pinned executable. It
downloads schemas at recorded release commits/tags and rejects unknown spec fields.
Auth tests use synthetic credentials and a fake curl executable; no cluster login
occurs. CI runs these checks for PRs and as a release gate.

Initialize each environment with `terraform init -backend=false -lockfile=readonly`,
then run `terraform validate`. Do not read personal tfvars or use a live apply as
a syntax test. Provider-free tests do not replace a reviewed account-specific plan
or the [live acceptance checklist](GITOPS.md#acceptance-monitoring-and-recovery).
