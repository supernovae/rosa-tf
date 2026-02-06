# Monitoring and Logging Layer for ROSA

This layer installs and configures a production-grade monitoring and logging stack for ROSA clusters, featuring Prometheus for metrics and Loki for log aggregation.

## Overview

The monitoring layer provides:

| Component | Purpose | Storage |
|-----------|---------|---------|
| **Prometheus** | Metrics collection and alerting | PVC (gp3-csi) |
| **AlertManager** | Alert routing and notification | PVC (gp3-csi) |
| **Loki** | Log aggregation and querying | S3 (STS auth) |
| **Vector** | Log collection (DaemonSet) | None |
| **COO** | Logging UI in OpenShift Console | None |

## Logging UI (Observe > Logs)

The Cluster Observability Operator (COO) is automatically installed to enable the **Observe > Logs** page in the OpenShift Console. This provides:

- Log viewing with filters, queries, and time ranges
- Log expansion for detailed information
- Integration with log-based alerts from Loki ruler
- Links to correlated metrics (Observe > Metrics)

The UIPlugin is configured with:
- LokiStack: `logging-loki`
- Schema: `viaq` (compatible with OCP 4.12+)
- Query timeout: 30 seconds
- Logs limit: 50 per query

**Supported versions:** OCP 4.12+ (both GovCloud and Commercial)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ROSA Cluster                                       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                     openshift-monitoring                                 ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────────┐  ││
│  │  │ Prometheus  │  │AlertManager │  │ User Workload Monitoring        │  ││
│  │  │ (100Gi PVC) │  │ (10Gi PVC)  │  │ (ServiceMonitors in user NS)    │  ││
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      openshift-logging                                   ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ ││
│  │  │   Vector    │  │    Loki     │  │    Loki     │  │      Loki       │ ││
│  │  │ (DaemonSet) │─▶│ Distributor │─▶│  Ingester   │─▶│    Compactor    │ ││
│  │  │             │  │             │  │             │  │  (retention)    │ ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └────────┬────────┘ ││
│  └──────────────────────────────────────────────────────────────┼──────────┘│
└─────────────────────────────────────────────────────────────────┼───────────┘
                                                                  │
                                                                  ▼
                                                    ┌─────────────────────────┐
                                                    │      AWS S3 Bucket      │
                                                    │  (STS/IRSA Auth)        │
                                                    │  - Log chunks           │
                                                    │  - Index files          │
                                                    └─────────────────────────┘
```

## Operator Channel Selection

The logging operators require specific channels based on OpenShift version:

| OpenShift Version | Operator Channel | Notes |
|-------------------|------------------|-------|
| 4.16, 4.17, 4.18  | `stable-6.2`     | GovCloud (uses `logging.openshift.io/v1` API) |
| 4.19+             | `stable-6.4`     | Commercial HCP (uses `observability.openshift.io/v1` API) |

Terraform automatically selects the correct channel based on `openshift_version`.

> **Note:** The monitoring layer is always applied by Terraform (direct method) because it requires environment-specific values (S3 bucket, IAM role) that Terraform creates. The `applicationset` method is for your own additional static resources, not for core layers.

## Prerequisites

1. **Fresh Cluster**: This layer assumes no existing monitoring customizations
2. **S3 Bucket**: Created by the `modules/gitops-layers/monitoring` Terraform module
3. **IAM Role**: STS-enabled role for Loki S3 access
4. **StorageClass**: `gp3-csi` (default on ROSA)

## Configuration

### Terraform Variables

```hcl
# Enable the monitoring layer
enable_layer_monitoring = true

# Retention configuration (default: 30 days)
monitoring_retention_days = 30  # Production
# monitoring_retention_days = 7   # Development

# Storage sizing
monitoring_prometheus_storage_size = "100Gi"  # 30-day retention
# monitoring_prometheus_storage_size = "50Gi"   # 7-day retention

# Storage class (default: gp3-csi)
monitoring_storage_class = "gp3-csi"
```

### Environment-Specific Defaults

| Environment | Retention | Prometheus Storage | Notes |
|-------------|-----------|-------------------|-------|
| Development | 7 days | 50Gi | Lower costs, faster queries |
| Production | 30 days | 100Gi | Compliance, troubleshooting |
| GovCloud | 30 days | 100Gi | FedRAMP requirements |

## API Version

**Minimum Supported**: OpenShift 4.16 with Cluster Logging Operator 6.x

This layer uses the Observability API which is the standard for Cluster Logging Operator 6.x:

| Component | API Group | Version |
|-----------|-----------|---------|
| LokiStack | `loki.grafana.com` | `v1` |
| ClusterLogForwarder | `observability.openshift.io` | `v1` |

The `ClusterLogForwarder` resource includes a `collector` section that deploys the Vector
collector DaemonSet and configures log forwarding pipelines.

## Verification Commands

After deployment, run the verification script or use these commands:

### Task 1: Verify Prometheus Storage Binding

```bash
# Check PVC status
oc get pvc -n openshift-monitoring -l app.kubernetes.io/name=prometheus

# Expected output:
# NAME                      STATUS   VOLUME   CAPACITY   STORAGECLASS
# prometheus-k8s-db-...     Bound    pvc-...  100Gi      gp3-csi

# Verify storage class
oc get pvc -n openshift-monitoring -o jsonpath='{.items[*].spec.storageClassName}' | tr ' ' '\n' | sort -u

# Check Prometheus pods
oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus
```

### Task 2: Verify Loki STS Role Assumption

```bash
# Check S3 credentials secret
oc get secret -n openshift-logging logging-loki-s3 -o yaml

# Verify role_arn is set
oc get secret -n openshift-logging logging-loki-s3 -o jsonpath='{.data.role_arn}' | base64 -d

# Check Loki pods for STS errors
oc logs -n openshift-logging -l app.kubernetes.io/component=ingester --tail=50 | grep -i "sts\|assume\|credential"

# Verify Loki components are running
for component in distributor ingester querier compactor; do
  echo -n "$component: "
  oc get pods -n openshift-logging -l app.kubernetes.io/component=$component -o jsonpath='{.items[0].status.phase}'
  echo
done
```

### Task 3: Verify Retention Policy

```bash
# Check Prometheus retention
oc get prometheus -n openshift-monitoring k8s -o jsonpath='{.spec.retention}'
# Expected: 720h (30 days)

# Check LokiStack retention
oc get lokistack -n openshift-logging logging-loki -o jsonpath='{.spec.limits.global.retention.days}'
# Expected: 30

# Verify compactor is running (enforces retention)
oc get pods -n openshift-logging -l app.kubernetes.io/component=compactor

# Check compactor logs for retention activity
oc logs -n openshift-logging -l app.kubernetes.io/component=compactor --tail=100 | grep -i "retention\|delete"
```

### Task 4: Verify Metric Scraping

```bash
# Check ServiceMonitors in openshift-logging
oc get servicemonitor -n openshift-logging

# Verify Vector collector metrics are being scraped
oc get servicemonitor -n openshift-logging collector-metrics -o yaml

# Check Prometheus targets (requires port-forward)
oc port-forward -n openshift-monitoring svc/prometheus-k8s 9090:9090 &
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.namespace=="openshift-logging") | .labels.job'
```

### Task 5: Verify Log Forwarding

```bash
# Check ClusterLogForwarder status
oc get clusterlogforwarder -n openshift-logging instance -o yaml

# Verify Vector collector DaemonSet
oc get ds -n openshift-logging collector

# Check for log ingestion
oc exec -n openshift-logging -l app.kubernetes.io/component=distributor -- wget -qO- 'http://localhost:3100/metrics' | grep "loki_distributor_lines_received_total"

# Query recent logs via Loki
oc exec -n openshift-logging -l app.kubernetes.io/component=querier -- wget -qO- 'http://localhost:3100/loki/api/v1/query?query={log_type="infrastructure"}&limit=5'
```

## Automated Verification Script

Run the included verification script:

```bash
# From the monitoring layer directory
./verify-monitoring.sh

# With verbose output
./verify-monitoring.sh --verbose
```

## Alerting Rules

The layer includes PrometheusRules for monitoring stack health:

| Alert | Severity | Threshold | Description |
|-------|----------|-----------|-------------|
| `PrometheusStorageNearFull` | Warning | 85% | Prometheus PVC usage high |
| `PrometheusStorageCritical` | Critical | 95% | Prometheus PVC nearly full |
| `LokiIngestionFailures` | Warning | >0 | Loki rejecting log entries |
| `LokiCompactorNotRunning` | Warning | absent | Retention not being enforced |
| `LokiS3OperationFailures` | Warning | >0 | S3 access issues |
| `VectorDroppingEvents` | Warning | >0 | Log collector backpressure |
| `VectorCollectorNotReady` | Warning | <desired | Collector pods not ready |
| `AlertManagerStorageNearFull` | Warning | 85% | AlertManager PVC usage high |

## Troubleshooting

### Prometheus PVCs Not Binding

```bash
# Check StorageClass exists
oc get sc gp3-csi

# Check for pending PVCs
oc get pvc -n openshift-monitoring

# Check events
oc get events -n openshift-monitoring --sort-by='.lastTimestamp'
```

### Loki S3 Authentication Failures

```bash
# Verify secret has correct values
oc get secret -n openshift-logging logging-loki-s3 -o yaml

# Check IAM role trust policy
aws iam get-role --role-name <cluster-name>-loki --query 'Role.AssumeRolePolicyDocument'

# Test S3 access from Loki pod
oc exec -n openshift-logging -l app.kubernetes.io/component=ingester -- aws s3 ls s3://<bucket-name>/
```

### Vector Not Collecting Logs

```bash
# Check DaemonSet status
oc get ds -n openshift-logging collector -o wide

# Check Vector logs
oc logs -n openshift-logging -l app.kubernetes.io/component=collector --tail=100

# Verify ClusterLogForwarder status
oc get clusterlogforwarder -n openshift-logging instance -o jsonpath='{.status.conditions}'
```

### High Disk Usage Alerts

```bash
# Check current usage
oc exec -n openshift-monitoring prometheus-k8s-0 -- df -h /prometheus

# Options:
# 1. Increase PVC size (edit cluster-monitoring-config)
# 2. Reduce retention period
# 3. Add metric relabeling to drop high-cardinality series
```

## References

- [OpenShift Monitoring Documentation](https://docs.openshift.com/container-platform/latest/observability/monitoring/monitoring-overview.html)
- [Loki Operator Documentation](https://docs.openshift.com/container-platform/latest/observability/logging/log_storage/installing-log-storage.html)
- [Cluster Logging Operator](https://docs.openshift.com/container-platform/latest/observability/logging/cluster-logging-deploying.html)
- [ROSA Monitoring Best Practices](https://docs.openshift.com/rosa/observability/monitoring/configuring-the-monitoring-stack.html)
