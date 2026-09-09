# Contributing to ROSA Terraform 2.0

Use Terraform from `.terraform-version`, Python 3.12, and approved locally
installed lint/security tools. Install pre-commit through your normal verified
package workflow, then run `pre-commit install`. There is no automatic remote
shell installer or documentation-overwrite target.

## Development workflow

1. Create a feature branch; keep credentials, state and private tfvars out of Git.
2. Change the module, all applicable roots, canonical guide and examples together.
3. Run `make fmt`, `make validate-all`, `make lint`, `make security` and
   `uv run scripts/check-examples.py` with approved tool versions.
4. Run the affected module's mocked `terraform test` and layer contract checks
   listed in [.github/workflows/security.yml](../.github/workflows/security.yml).
5. Review the exact diff and stage only intended files. Open a PR with verification
   results and clearly identify checks not run. Resolve CI findings before merge.

Do not weaken a check, silently force field ownership, add a compatibility alias,
or introduce a shell fallback for a supported provider resource. Test negative
paths as well as happy paths. Add mock tests for destructive-operation guards,
partition boundaries and invalid feature combinations.

## Deployment and releases

Live tests require separately authorized accounts, spend and access; unit tests
must not deploy cloud resources. Follow [deployment](DEPLOYMENT.md) for phase
ordering and explicit versions, and [security](SECURITY.md) for credentials and
scan exceptions. Never put state or saved plans in public CI artifacts.

2.0 is a fix-forward release, not a supported in-place 1.x upgrade. Do not tag
while RHCS remains prerelease. [Release readiness](ROADMAP.md) requires stable
provider adoption, all four target acceptance results and explicit approval.
The release workflow checks both metadata and actual provider constraints/locks.
