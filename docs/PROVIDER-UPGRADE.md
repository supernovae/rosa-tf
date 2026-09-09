# 2.0 provider baseline

Development baseline reviewed 2026-09-09:

| Component | Selected version |
| --- | --- |
| Terraform | 1.16.1 |
| terraform-redhat/rhcs | **1.7.8**, exact stable pin |
| hashicorp/aws | 6.63.0 |
| hashicorp/kubernetes | 3.2.1 |
| alekc/kubectl | 2.4.1 |
| hashicorp/random | 3.9.0 |
| hashicorp/time | 0.14.1 |
| hashicorp/tls | 4.4.0 |
| hashicorp/external | 2.4.1 |
| hashicorp/local | 2.9.0 |
| hashicorp/null | 3.3.1 where still required |

Stable RHCS 1.7.8 was published on 2026-09-09. Its Git tree is identical to
1.7.8-prerelease.2; stable binaries and Linux/macOS checksums were independently
resolved. The temporary prerelease acknowledgment input is removed; release
approval remains false.

On future upgrades, compare the final schema and regenerate/review
[rhcs-capabilities.json](rhcs-capabilities.json). Run the capability checker,
all mocked cluster/pool tests, root validation and security scans. The checker
fails on new/removed resources, writable fields or types, and missing core wiring.

Do not infer region/platform support from an available provider field. Native
creation-only options remain immutable; do not create a second owner for default
worker pools, IdPs or log forwarders. See [capabilities](RHCS-CAPABILITIES.md).

2.0 is a fix-forward baseline with no supported 1.x state migration.
