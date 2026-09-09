# Reviewed two-phase deployment

This is the 2.0 development baseline, not an approved production release or a
1.x state migration. Stable RHCS `1.7.8` is pinned with verified locks; live
acceptance and release approval still precede a 2.0 tag. See the
[native capability audit](RHCS-CAPABILITIES.md).

## Prerequisites

Use short-lived AWS credentials/SSO in the intended account and partition. Verify
caller identity and region without printing credentials. Configure the existing
root-specific RHCS authentication inputs through your approved secret manager
or environment: commercial service-account credentials or the GovCloud token.
Do not put secrets in `.tfvars`, shell history, PRs, logs or plan artifacts.

Use Terraform from `.terraform-version`. Initialize with committed locks and
`-lockfile=readonly`; do not routinely run `init -upgrade` in deployment automation.
Use an approved remote state backend with encryption, locking, restricted access
and recovery/versioning. Local state, saved plans and bootstrap passwords are
sensitive even when Terraform marks their outputs sensitive.

Select a current OpenShift patch from the target account/region and architecture
using the ROSA/OCM version catalog. Record it explicitly as `openshift_version`
in your private base. Confirm the intersection of cluster and selected layer
support: current OADP does not accept 4.18; Virtualization/AI need their own
platform and hardware checks. No single hardcoded patch is promised across all
four roots. Do not bypass a layer support gate to make a seed apply.

Provision HCP account IAM roles through `environments/account-hcp` first. For
BYO-VPC, verify subnet/AZ mapping, DNS, private connectivity, approved egress,
endpoint policies and available IP space. GovCloud HCP defaults to zero-egress;
that does not automatically provide every operator image, private Git source or
service endpoint. See [network prerequisites](ZERO-EGRESS.md).

Terraform-created VPCs have a deny-all default security group; workloads and
endpoints must use dedicated groups. BYO-VPC default groups are not adopted by
this module and must be reviewed by their owner. If independently adapting this
code to an existing VPC, inventory interfaces using its default group first:
adopting the group removes its existing ingress and egress rules and can interrupt
dependent workloads. This is not an in-place 1.x upgrade procedure.

## Phase 1: infrastructure

Copy the appropriate `cluster-dev.tfvars` or `cluster-prod.tfvars` seed to an
ignored local file. These are posture examples, not evidence of production
readiness. Supply your verified OpenShift version and identity/network choices.

From the selected environment root:

```sh
terraform init -lockfile=readonly
terraform plan -var-file=private.tfvars -out=reviewed.tfplan
# Review account, region, private endpoints, IAM, costs and every change first.
terraform apply reviewed.tfplan
```

Keep `install_gitops = false` in Phase 1. No cluster-facing provider should create
platform resources while the cluster endpoint/identity is still being established.
Cluster deletion protection defaults on. This is not permission to remove data
protection merely because a plan proposes replacement.

## Phase 2: platform, then workloads

Establish private network access from the deployment runner. Verify the API
hostname, trusted CA and certificate chain; use approved authentication without
disabling verification. Bootstrap credentials are privileged and stored in
state: secure them, establish organizational identity/RBAC and stop using the
bootstrap administrator for normal work.

Use the same private base and state, plus the selected GitOps overlay and layer
overlays. All optional layers start disabled. Verify regional catalogs, mirrors,
support confirmations, node placement, storage and recovery prerequisites first.
Use a new reviewed saved plan for Phase 2. Where operator approval is Manual,
inspect the InstallPlan and approve through an authorized operator session.

Do not point Argo CD at Terraform-owned layer templates. Delegate only approved
workload repositories/namespaces and keep automatic pruning off until reviewed.
Sync waves do not order independent Applications or Terraform applies.

## Acceptance and release evidence

Record actual cluster/CSV/operand versions, architectures, access tests and
support decisions for each commercial/GovCloud Classic/HCP target. Verify IAM
denials as well as successes, private DNS/routes, pod scheduling and alert
delivery. Perform real container/VM data restore tests, not just CR status checks.
Spot/route schema tests do not establish regional service eligibility.

The cluster modules now forward explicit version changes to RHCS. Review the
provider-scheduled upgrade and required acknowledgments; reconcile a version that
was advanced outside Terraform before planning. For HCP, complete the control-plane
upgrade and refresh its observed version before changing pool targets. Native
upgrade support is not a supported 1.x-to-2.0 repository state migration.
