# Secure deployment and verification

This repository is 2.0 development infrastructure code, not a certification or a
production support guarantee. Start with [deployment](DEPLOYMENT.md),
[release gates](ROADMAP.md), and [FedRAMP responsibilities](FEDRAMP.md).

## Controls and boundaries

Seeds select private access, encrypted etcd, customer-managed KMS and cluster
deletion protection. Optional layers, public access helpers and Spot are opt-in.
GovCloud HCP seeds select zero egress. Validate identity, required endpoints,
image provenance and restore procedures before application onboarding.

Use short-lived AWS/OCM credentials, explicit AWS partitions and narrowly scoped
OIDC subjects. Never put private keys or tokens in examples. State and saved
plans contain secrets even when outputs are marked sensitive: encrypt remote
state, restrict access, enable locking/versioning, and do not publish plan artifacts.
Native route configuration uses TLS Secret references, never key material.

GitOps and Terraform must not own the same object fields. Server-side apply does
not force ownership conflicts. Review drift, manual operator InstallPlans,
retention and deletion protection before any apply or destroy. The VPC inventory
helper is read-only; no automatic broad security-group cleanup is performed.

## Verification

GitHub workflows pin action revisions to immutable commits, with Dependabot
reviewed updates. Checkov policy findings and high/critical Grype findings fail
CI; ShellCheck, Gitleaks, TruffleHog and Terraform tests provide complementary
checks. YAML style lint is advisory. No scanner establishes absence of vulnerabilities.

Run `make security` with approved locally installed tooling. It fails when a tool
fails or reports blocking findings; installation is not attempted by piping
remote scripts into a shell. CI is authoritative for the checked revision, not
historical scan counts in documentation.

Policy exceptions remain visible in [.checkov.yml](../.checkov.yml). They are
risk decisions, not proof of compliance: review applicability for the actual
plan and narrow exceptions when resolving scanner findings. Do not add broad
exceptions or soft-fail settings merely to get a green build. Regional endpoint,
operator, identity and recovery checks still require live acceptance testing.

## Operational evidence

Retain approved plans, identity/RBAC reviews, deployment and operator versions,
private-network tests, dashboard/alert ownership and successful restore evidence.
Backups must be recoverable independently of the source cluster and its keys;
see [OADP](OADP.md) and [observability](OBSERVABILITY.md). Report vulnerabilities
privately to the repository owner; never attach credentials, state or customer data.
