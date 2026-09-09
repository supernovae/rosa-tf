# Curated 2.0 examples

Examples are seeds/overlays, not ready-to-apply production configurations. Use a
private cluster base with an explicitly verified regional `openshift_version`.
The branch pins stable RHCS 1.7.8; repository release approval remains pending;
see [deployment](../docs/DEPLOYMENT.md). No 1.x migration is supported.

| Example | Scope and prerequisites |
| --- | --- |
| `cluster-only.tfvars` | Phase 1 safety overlay; all roots; apply last |
| `provider-options.tfvars` | All roots; native DNS prefix, timeout and OCM properties |
| [RHCS companion resources](rhcs-companion-resources) | Native identity, kubelet and mirror composition; review placeholders and separate ownership |
| `zeroegress.tfvars` | Commercial HCP scenario; approved private endpoints/mirrors |
| `byovpc.tfvars` | Commercial HCP BYO-VPC; replace all network IDs |
| `byovpc-classic-prod.tfvars` | Classic BYO-VPC scenario; approved subnet/AZ layout |
| `observability.tfvars` | HCP ARM observability scenario; operand architecture/support checks |
| `certmanager.tfvars` | HCP certificate/custom-ingress scenario; approved DNS zone and issuer |
| `autonode.tfvars` | HCP compute overlay; approved AutoNode platform support |
| `hcp-spot.tfvars` | HCP overlay; interruption-tolerant workloads only |
| `component-routes.tfvars` | All roots, phase 2; trusted TLS Secrets/DNS ready; OAuth Classic-only |
| `gitops-workloads.tfvars` | All roots; explicit trusted workload repo, groups and namespace |
| `efs-storage.tfvars` | All roots; actual worker SGs, supported EFS catalog and AWS Backup |
| `netappstorage.tfvars` | All roots; supported Trident, private endpoints, CA and external credentials |
| `oadp.tfvars` | All roots subject to OADP/CSI support; paused explicit backup scope |
| `openshiftai.tfvars` | AI overlay; verify platform, hardware, operator and model prerequisites |
| `ocpvirtualization.tfvars` | Classic VM overlay; vendor confirmation and supported bare metal/storage |

Pass overlays after the private base. Fields in later files override earlier
ones; lists such as `machine_pools` replace the whole list, not individual pools.
Do not accidentally drop on-demand or storage-authorized pools when combining
examples. For Phase 1, pass `cluster-only.tfvars` last; Phase 2 uses the same base
and state with explicitly selected layers.

HCP uses nested `autoscaling` in `machine_pools`; omit `replicas` when enabled.
The unsupported HCP cluster-wide autoscaler inputs no longer exist. Spot capacity
does not replace on-demand platform capacity. Current examples avoid public
API/ingress defaults and do not contain reusable credentials.

Acceptance fixtures: [GitOps workload](gitops-workload/kustomization.yaml),
[observability](observability), [NetApp](netapp/README.md),
[VM recovery](oadp/README.md), [EFS](efs/README.md). Review placeholders, images,
TLS, namespaces and authorization before applying anything.

`uv run scripts/check-examples.py` checks declared inputs and deployment
contracts. It does not verify real network IDs, regional availability or support.
