# Terraform and provider baseline

Verified on September 8, 2026. Use Terraform 1.16.1 (`.terraform-version`);
all maintained modules require Terraform >= 1.16.1 and < 2.0.

| Provider | Verified stable version |
|----------|-------------------------|
| terraform-redhat/rhcs | 1.7.7 |
| hashicorp/aws | 6.63.0 |
| hashicorp/kubernetes | 3.2.1 |
| alekc/kubectl | 2.4.1 |
| hashicorp/random | 3.9.0 |
| hashicorp/time | 0.14.1 |
| hashicorp/external | 2.4.1 |
| hashicorp/null | 3.3.1 |
| hashicorp/tls | 4.4.0 |
| hashicorp/local | 2.9.0 |

RHCS 1.7.8-prerelease.2 is not a stable release, even though GitHub labels it
latest. The maintained environments use RHCS 1.7.7. See the official
[RHCS releases](https://github.com/terraform-redhat/terraform-provider-rhcs/releases)
and [Terraform release](https://github.com/hashicorp/terraform/releases/tag/v1.16.1).

## Reproducible installation

The [example catalog](../examples/README.md) distinguishes full scenarios from
overlays and documents two-phase deployment. Run
`uv run scripts/check-examples.py` to check tracked sample input contracts;
CI runs the same check. This does not validate regional availability or replace
a live, reviewed plan. Remote-state examples use native S3 locking, and
`make clean` preserves state and dependency lockfiles.

The four Commercial/GovCloud Classic/HCP environments, account preparation,
and the BYO VPC helper track their dependency lockfiles. Hashes cover macOS ARM64
and Linux AMD64. CI uses Terraform 1.16.1 and `init -lockfile=readonly`.
Library modules declare compatible ranges with an upper major-version bound.

Install Terraform 1.16.1 using your version manager or the
[official installer](https://developer.hashicorp.com/terraform/install), then:

```sh
cd environments/commercial-hcp
terraform init -lockfile=readonly
terraform validate
terraform plan -var-file=cluster-dev.tfvars
```

For future dependency updates, run `make upgrade-providers ENV=commercial-hcp`,
review release notes and the lockfile diff, and repeat for the other roots.
Run `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64`
to retain both development and CI checksums. Commit the resulting lockfiles.
Normal initialization and `make clean` preserve the selected versions.

## Existing cluster migration

Both cluster modules now use native RHCS `admin_credentials` to create an
htpasswd administrator during cluster creation. The deprecated
`rhcs_group_membership` resource and the separate bootstrap IDP are no longer
used for new clusters. See the provider's
[Classic](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/docs/resources/cluster_rosa_classic.md)
and [HCP](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/docs/resources/cluster_rosa_hcp.md)
resource documentation.

For existing clusters, `removed` blocks with `destroy = false` relinquish
Terraform ownership of the old IDP and membership without deleting either.
Keep these migration declarations until all states have upgraded. The existing
random-password addresses and credential outputs are retained. Native credentials
are creation-only and ignored on updates so an older cluster is not sent an
unsupported credential modification. Native credential outputs use the stored
values; older clusters fall back to the existing generated password.

Review the first plan: the old admin resources should say they will no longer
be managed, not that they will be destroyed. No cluster replacement is required
by this migration. Back up your state using your normal secure process before
applying; the state contains sensitive credentials.

Admin creation settings now apply at cluster creation. Changing a username or
`create_admin_user` later does not create, rotate, or revoke an existing login.
Manage subsequent identity changes through your production identity/RBAC process.
Do not replace the retained random-password resource to rotate a migrated login:
that would change the reported password without changing the actual user.

## HCP autoscaler correction

The old HCP module used the Classic `rhcs_cluster_autoscaler` resource.
It now selects `rhcs_hcp_cluster_autoscaler`, but RHCS 1.7.7 explicitly documents
that endpoint as unavailable. Validation therefore requires
`cluster_autoscaler_enabled = false` for HCP. HCP machine-pool autoscaling works
independently: configure pool `autoscaling` and minimum/maximum replicas.
Classic cluster-wide autoscaler configuration remains available.

Any previously tracked Classic autoscaler object under the HCP module is
forgotten without an API deletion. See the official
[HCP autoscaler limitation](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/docs/resources/hcp_cluster_autoscaler.md).

## Verification

All four environment configurations and account/VPC helper roots are validated
with the selected providers. Bootstrap regression tests mock every provider and
cover both partitions, disabled bootstrap, creation-only credentials, and
migration from the retired resource layout. The migration plan check rejects
any delete/replacement and requires both legacy admin resources to be forgotten.
The legacy test fixture intentionally uses the deprecated resource to represent
old state; production configuration does not instantiate it.

Run the regression tests after initializing each cluster module:

```sh
cd modules/cluster/rosa-hcp
terraform init -backend=false
bash ../../../scripts/test-bootstrap.sh
```

The legacy fixture uses empty native credential fields because Terraform 1.16.1
crashes when mocking a null nested object. It exercises the existing-credential
fallback and immutable-field preservation; it does not emulate a live RHCS API.
These checks do not provision clusters or prove a live deployment. Review a
credentialed plan for each target cluster before applying the upgrade.
