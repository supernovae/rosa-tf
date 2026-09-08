# Observability as an operated service

Reviewed 2026-09-08. Covers commercial/GovCloud ROSA Classic and HCP. Metrics,
alerts and logs are included; tracing, Network Observability and automated disaster
recovery are separate optional services.

## Supported releases

| Running OpenShift | Logging AND Loki channel | Qualification |
| --- | --- | --- |
| 4.16–4.18 | `stable-6.2` | EUS only: confirm operator entitlement/support with Red Hat |
| 4.19 | `stable-6.5` | Supported maintenance stream |
| 4.20–4.22 | `stable-6.6` | Latest verified release stream |

The [Red Hat lifecycle table](https://access.redhat.com/support/policy/updates/openshift_operators)
lists 6.6 GA on July 14, 2026 and 6.2 EUS through October 21, 2028. Logging/Loki
6.4 technically supports 4.18 but ended maintenance when 6.6 shipped; it is not a
supported modernization target. OpenShift coverage alone is not confirmation of
operator EUS entitlement. Unknown minors fail the compatibility precondition.

The platform metrics stack ships with OpenShift: do not install a separate
upstream Prometheus over it. COO remains on `stable`; current release notes list
1.5.2. Optional GA Perses dashboards require **COO >=1.5**. OLM resolves the patch
from the cluster catalog; defaults do not guarantee commercial bundles are in a
GovCloud/private catalog. See [COO releases and feature matrix](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html/red_hat_openshift_cluster_observability_operator_release_notes/cluster-observability-operator-release-notes).

Logging 6.6 adds three ingesters for extra-small/small stacks and authenticated
collector metrics endpoints. Operators now own their ServiceMonitors and health
rules here; we do not hard-code TLS/service names or obsolete metric names. We
also do not set its new platform collection-profile knob on ROSA-managed monitoring.
See [Logging 6.6 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.6/html/release_notes/logging-release-notes).

## How the stack works

| Signal | Collection/storage | User experience |
| --- | --- | --- |
| Platform metrics | ROSA-managed Prometheus/Alertmanager | Observe → Metrics, Dashboards, Alerting; SRE owns platform configuration |
| Application metrics | ServiceMonitor/PodMonitor → user Prometheus → Thanos Ruler/Alertmanager | PromQL, namespace alerts, optional Perses dashboards |
| Logs | Node-local Vector → Loki gateway/ingesters → S3; PVCs hold WAL/index/cache | Observe → Logs, LogQL and namespace-based authorization |
| Traces (separate) | Instrumented application → OpenTelemetry → supported trace store | Distributed tracing UI; not installed by this layer |

The layer enables `enableUserWorkload`, then configures persistent customer
Prometheus, Thanos Ruler and Alertmanager in `openshift-user-workload-monitoring`
on **both** Classic and HCP. It does not tune `prometheusK8s` or `alertmanagerMain`.
ROSA warns against changing platform components in `cluster-monitoring-config`;
use [user-workload configuration](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/epub/monitoring/getting-started).

Loki Operator lives in `openshift-operators-redhat`, Logging in `openshift-logging`,
and this repository's COO subscription in global `openshift-operators`. LokiStack
and ClusterLogForwarder live in `openshift-logging`. Application, infrastructure
and audit are distinct tenants—not an unrestricted single tenant. Do not grant
cluster-admin or blanket audit-log access just to let an application owner view logs.

## Preflight and installation

1. Verify the **running** cluster version, support coverage, catalog channels,
   machine types and storage class. Keep `openshift_version` aligned with reality:
   editing it does not upgrade existing clusters (versions are lifecycle-ignored).
   Perform approved ROSA/OCM upgrades first. Keep Logging and Loki on the same minor.
2. Use the two-phase cluster/GitOps workflow: create the cluster and pools first,
   then enable the layer in the environment's GitOps tfvars from a runner with
   private API access. Review a plan before applying.
3. Zero-egress GovCloud HCP needs approved mirrored catalogs **and all related
   images**, including both architectures. Subscriptions use `redhat-operators`
   in `openshift-marketplace`; provision that approved catalog or adapt subscriptions
   under one owner. Public registry/GitHub access is not supplied by zero egress.
   Confirm private regional S3/STS connectivity, DNS and endpoint policies allowing
   this bucket and role. Certificate, GitOps and other layers may need separate
   network accommodations.

~~~sh
oc get clusterversion version
oc get storageclass gp3-csi
oc get packagemanifest loki-operator -n openshift-marketplace -o yaml
oc get packagemanifest cluster-logging -n openshift-marketplace -o yaml
oc get packagemanifest cluster-observability-operator -n openshift-marketplace -o yaml
oc get nodes -L kubernetes.io/arch,node-role.kubernetes.io/monitoring
~~~

Inspect channel CSV versions, related images and `arm64` support in the actual
catalog. If unavailable, resolve the catalog/support issue rather than bypassing
it with an upstream or preview operator.

~~~hcl
install_gitops                     = true
enable_layer_monitoring            = true
monitoring_loki_size               = "1x.extra-small"
monitoring_retention_days          = 7
monitoring_prometheus_storage_size = "100Gi"
monitoring_storage_class           = "gp3-csi"
# Optional AFTER confirming COO >=1.5 in the regional catalog:
monitoring_enable_perses           = true
~~~

See [the HCP ARM infrastructure example](../examples/observability.tfvars). The
static layer Kustomization is **bootstrap only**, for 4.20–4.22, not the complete
Terraform deployment. Do not use Terraform and Argo/Kustomize to own the same objects.

## Application onboarding: prove a useful signal

Instrument a real application with a Prometheus/OpenMetrics endpoint and structured
stdout logs. [Application manifests](../examples/observability/application.yaml)
use namespace `observability-demo`, pod label `app: example-api`, port 8080 and
`/metrics`. Deploy your instrumented app there or adapt all namespace/selector/port
fields together. The sample does not deploy a public demo image.

1. Apply the adapted Namespace, Service, ServiceMonitor and PrometheusRule. A
   ServiceMonitor selects **Services**, and its endpoint port is the **Service
   port name**. The rule catches unhealthy targets and the no-series case.
2. Grant the team the documented `monitoring-edit` role in its namespace and
   appropriate read/query access for viewers. Limit network access to metrics to
   the monitoring namespace; use TLS/auth for sensitive endpoints. Sample HTTP
   is an internal starting point, not a reason to expose metrics through a Route.
3. In Observe → Metrics, scope to the namespace and run:

~~~promql
up{namespace="observability-demo",service="example-api-metrics"}
~~~

Expect one series per endpoint with value 1. Empty results are **not healthy**:
inspect endpoints, labels, namespace exclusions, NetworkPolicy, TLS and target
errors. Do not put app rules in `openshift-monitoring` or mark app namespaces
`openshift.io/user-monitoring=false`.

4. Generate a request with a unique, non-sensitive correlation ID and emit it in
   stdout. In Observe → Logs, choose application logs and query:

~~~logql
{kubernetes_namespace_name="observability-demo"} |= "obs-smoke-"
~~~

Verify the fresh timestamp/workload. Use the label browser if moving from ViaQ to
OpenTelemetry log format. HCP does not imply access to all service-owned control-plane
audit logs: verify the actual collected sources and additional ROSA export needs.

## Dashboards and actionable alerts

Start with built-in workload, compute, networking and Prometheus dashboards,
scoped to the team's namespace. A useful team overview includes request rate,
error ratio, p95 latency, saturation, restarts, scrape health and log links. Define
metric names in application instrumentation before copying queries; a missing
histogram is not zero latency.

Enable `monitoring_enable_perses` after checking COO >=1.5, then open Observe →
Dashboards (Perses). Create a namespace dashboard using the OpenShift-authenticated
Prometheus datasource. Test as an ordinary team member; never provision a shared
cluster-admin token. Export dashboard CR/YAML into the team's GitOps repo and
validate its served API with `oc explain` and server-side dry run. Use the supported
Grafana import/conversion workflow for existing dashboards, then test each panel,
query and plugin. See the [Perses guide](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html/ui_plugins_for_red_hat_openshift_cluster_observability_operator/perses-dashboard).

The dedicated user Alertmanager accepts namespaced `AlertmanagerConfig` objects.
Adapt [the receiver example](../examples/observability/alertmanagerconfig.yaml),
provision its referenced Secret through an approved secret system, and send a
firing **and resolved** test alert to an owned destination. Keep namespace matching
enabled so one project cannot capture another's alerts. Verify the installed API
with `oc explain` and server-side dry run. See [ROSA's configuration reference](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws_classic_architecture/4/html/monitoring/config-map-reference-for-the-cluster-monitoring-operator).

Every production alert needs severity, owner, annotations, runbook and response
expectations. In nonproduction, stop the test app's metrics endpoint, confirm
notification, restore it and confirm resolution. Silences need owner and expiry.
Verify platform logging alerts/routing separately with the administrator: user
Alertmanager does not automatically receive all platform alerts. Do not duplicate
operator-supplied alerts using guessed collector or Loki metrics.

## ARM, HCP multi-architecture and economics

ROSA HCP supports Graviton ARM worker pools alongside x86 using a multi-architecture
payload. Choose a supported ARM instance type in the existing RHCS node pool;
no preview provider is needed for this placement. It does not change the hosted
control plane. Keep Classic on its supported x86 path; do not infer Classic ARM
support from HCP. See [ROSA worker architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/epub/introduction_to_rosa/about-hcp).

The example uses memory-balanced `m7g.4xlarge` (16 vCPU, 64 GiB), not an assertion
that compute-optimized nodes are always best for Prometheus/Loki. The selector
includes `kubernetes.io/arch=arm64` plus the monitoring pool label. Placement covers
Loki and user Prometheus/Thanos Ruler/Alertmanager, **not** ROSA platform monitoring.
Operator/UI pods may stay on x86. Vector needs both image architectures because
it must collect from every eligible worker. `PreferNoSchedule` softly discourages
other workloads; it does not attract monitoring pods—the selector does that.
Before using a hard taint, check collector/platform DaemonSet tolerations.

AWS lists M7g in GovCloud, but regional EC2 availability does not establish ROSA
account/version support or AZ capacity. Verify ROSA's regional machine-type list
and [EC2 offerings](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-regions.html).
When adapting the commercial sample, retain GovCloud's private, zero-egress
network and approved cluster release; do not copy commercial network defaults.

AWS advertises [up to 20% lower instance cost versus comparable x86](https://aws.amazon.com/ec2/graviton/),
not a measured Loki result or 20% off the entire cluster. Compare equal memory,
vCPU, region, tenancy and purchase model, then benchmark ingestion, queries,
cardinality and failure headroom.

**Illustration, not a regional quote:** three nodes, 730 hours/month, x86 at
$1.00/hour and ARM at $0.80/hour:

| Monthly cost | x86 | ARM |
| --- | ---: | ---: |
| Monitoring EC2 pool | $2,190 | $1,752 |
| EC2-only saving | — | $438/month; $5,256/year |
| Other costs (illustrative fixed amount) | $1,000 | $1,000 |
| Total | $3,190 | $2,752; 13.7% lower |

Replace rates with [AWS Pricing Calculator](https://calculator.aws/) quotes for
**your commercial or GovCloud region**. Formula: `730 × node_count × hourly_rate`.
Include ROSA worker/service and HCP fees, EBS GB/IOPS/throughput, S3 current and
noncurrent versions/requests, KMS, cross-AZ traffic, private endpoints and backups.
A monitoring/infra label is not evidence of waived ROSA fees. Compare marginal
pool cost separately from Classic-versus-HCP architecture costs. Savings Plans
and utilization change the result.

Size from measured ingestion and active series, not retention alone. Retain
headroom for failures and rolling updates. Multiple nodes in one AZ are not AZ
resilience: use multi-AZ production pools and account for EBS AZ affinity when
moving stateful pods. Consult the selected Loki release's resource envelopes
instead of assuming a fixed node count guarantees a given stack size.

## Retention, recovery and acceptance

`monitoring_retention_days` sets user metrics and Loki compactor retention and
expires **noncurrent** S3 versions after that many days. It does not independently
expire live chunks/indexes. Versioning extends physical data lifetime/cost beyond
query retention. Active Loki storage is not configured with Glacier or Object Lock.

Read [AWS recovery runbooks](OBSERVABILITY-AWS-RECOVERY.md). A retained S3 bucket
is not a complete backup; remote-write is not a backup of dashboards or rules.

Run `gitops-layers/layers/monitoring/verify-monitoring.sh` from an authenticated
private-network runner. It checks readiness, PVCs and collectors, fails on missing
resources, and does not print credentials. It does **not** prove successful use.
Acceptance must include a fresh log query, app scrape, non-admin dashboard,
firing/resolved notification, node-drain exercise, S3 write/query health, recovery
rehearsal with measured RPO/RTO and monthly cost baseline. Review drops/429s,
PVC pressure, cardinality, retention and notification failures regularly.

## Existing-installation migration

This is not an unattended upgrade. Export ConfigMaps, subscriptions, Loki schema
history, rules and dashboards. Review existing user-workload config ownership:
the layer manages the whole `config.yaml`, so reconcile remote-write/receiver
settings rather than overwriting another owner's configuration. Removing old
`prometheusK8s`/`alertmanagerMain` overrides can roll platform components and change
storage/retention; coordinate with ROSA SRE and protect required history first.
User Prometheus does not inherit platform TSDB history. ARM relocation may need
a controlled EBS/AZ migration rather than just changing selectors.

The obsolete Terraform `monitoring-stack-alerts` rule is removed; the collector
ServiceMonitor is relinquished without deletion because Logging reconciles it.
Confirm operator ownership/reconciliation; review any orphan before explicitly
removing it. Preserve existing Loki schema histories; do not replace them with
this new-install template's v13 entry. Follow supported sequential operator upgrade
procedures. **Do not downgrade an existing 6.4 stack to 6.2** to match a 4.18
default: resolve the lifecycle situation with Red Hat. Slow catalogs can outlast
bootstrap delays; check CSV/CRD readiness before retrying. LokiStack and forwarder
resources additionally wait for Ready conditions.
