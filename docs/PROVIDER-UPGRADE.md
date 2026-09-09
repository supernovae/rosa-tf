# 2.0 provider baseline

Development baseline reviewed 2026-09-09:

| Component | Selected version |
| --- | --- |
| Terraform | 1.16.1 |
| terraform-redhat/rhcs | **1.7.8-prerelease.2**, exact development pin |
| hashicorp/aws | 6.63.0 |
| hashicorp/kubernetes | 3.2.1 |
| alekc/kubectl | 2.4.1 |
| hashicorp/random | 3.9.0 |
| hashicorp/time | 0.14.1 |
| hashicorp/tls | 4.4.0 |
| hashicorp/external | 2.4.1 |
| hashicorp/local | 2.9.0 |
| hashicorp/null | 3.3.1 where still required |

The published RHCS prerelease provides HCP Spot settings and component routes.
Its GitHub release flag does not make it stable. The
[official provider policy](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)
distinguishes stable versions from suffix-bearing prereleases. This repository
blocks 2.0 tagging until stable RHCS and reviewed release approval.

Use `terraform init -lockfile=readonly` for normal deployments. Provider changes
belong in a separate reviewed change with final release notes, installed schema
checks, refreshed `linux_amd64` and `darwin_arm64` checksums and all tests. Never
edit a lock version without its package hashes, or substitute an unverified
local binary for a registry-signed release.

The maintained `terraform-redhat/rhcs` provider is used in both partitions. There
is no alternate preview-provider namespace or broad prerelease version range.
ROSA version/API/region eligibility is separate from Terraform provider selection.

2.0 has no supported 1.x state migration. Removed compatibility bootstrap
fixtures do not establish a safe upgrade path. Review retained data and account
resources independently; use [deployment](DEPLOYMENT.md) and
[operations](OPERATIONS.md), not state surgery or provider replacement recipes.
