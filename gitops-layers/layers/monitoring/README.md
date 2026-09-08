# Monitoring layer manifests

The Terraform operator module renders and sequences these manifests. Start with
[the operations guide](../../../docs/OBSERVABILITY.md) for support, installation,
application onboarding, dashboards, alerts, ARM economics and migration notes.
See [AWS recovery](../../../docs/OBSERVABILITY-AWS-RECOVERY.md) for optional backup.

- `logging-channels.yaml`: reviewed minor-version compatibility. Logging/Loki
  6.6 for OpenShift 4.20–4.22, 6.5 for 4.19, 6.2 EUS for 4.16–4.18 (confirm coverage).
- `cluster-monitoring-config.yaml`: enables user monitoring only; ROSA owns the
  platform stack. `user-workload-monitoring-config.yaml.tftpl` controls customer
  metrics retention, PVCs, node placement and namespace alert routing.
- LokiStack uses v13 storage, explicit token credentials, three OpenShift tenants
  and optional placement. Preserve schema history on existing stacks.
- ClusterLogForwarder uses `observability.openshift.io/v1` on every supported
  stream; Vector collects from all eligible workers. Operators own metrics scrapes
  and health alerts, including the correct release-specific TLS/authentication.
- COO provides the logging UI. Optional `uiplugin-monitoring.yaml` enables GA
  Perses after COO >=1.5 is verified in the target catalog.

The Kustomization is **bootstrap only for 4.20–4.22**. It omits resources requiring
new CRDs, S3/IAM values and UWM placement; it is not a complete standalone install.
Do not apply it alongside Terraform management. For another minor, change both
operator subscriptions together according to the support matrix before bootstrap.

`verify-monitoring.sh` is a read-only readiness check requiring authenticated `oc`
and `jq`. It fails on missing/unready operators, collectors, pods and PVCs. Complete
the guide's fresh-log, scrape, dashboard and delivered-alert acceptance tests too.

Static checks: `terraform -chdir=tests/monitoring test` and
`uv run scripts/check-monitoring-schemas.py` from the repository root (Terraform
1.16.1 on PATH). These do not replace catalog, admission or live-cluster tests.
