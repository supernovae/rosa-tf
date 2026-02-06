# Observability Stack for ROSA

This document covers the monitoring, logging, and observability configuration for ROSA clusters deployed with this Terraform module.

## Overview

The observability stack includes:

| Component | Purpose | Operator |
|-----------|---------|----------|
| **Prometheus** | Metrics collection and alerting | Built-in (openshift-monitoring) |
| **AlertManager** | Alert routing and notifications | Built-in (openshift-monitoring) |
| **Loki** | Log aggregation and querying | Loki Operator |
| **Vector** | Log collection (DaemonSet) | Cluster Logging Operator |
| **COO** | Console UI for logs | Cluster Observability Operator |

## Operator Installation Architecture

Per Red Hat documentation, the operators are installed in specific namespaces:

| Operator | Namespace | Why |
|----------|-----------|-----|
| **Loki Operator** | `openshift-operators-redhat` | Avoids conflicts with community operators; ensures ServiceMonitor TLS works correctly |
| **Cluster Logging Operator** | `openshift-logging` | Manages ClusterLogForwarder and Vector collectors |
| **Cluster Observability Operator** | `openshift-logging` | Manages UIPlugin for console log viewing |

The **LokiStack CR** and **ClusterLogForwarder CR** are created in `openshift-logging` namespace, but the Loki Operator watches all namespaces and manages them from `openshift-operators-redhat`.

This architecture ensures:
- ServiceMonitor TLS certificates have correct serverName
- No conflicts with community operators in `openshift-operators`
- Proper metrics scraping by Prometheus

## Enabling Observability

Enable the monitoring layer in your `tfvars` file:

```hcl
enable_layer_monitoring = true
```

## LokiStack Sizing

The `monitoring_loki_size` parameter controls resource allocation for all Loki components.

### Available Sizes

| Size | Use Case | Resources per Component | Minimum Cluster |
|------|----------|------------------------|-----------------|
| `1x.demo` | Demo/testing only | Minimal | 2 nodes |
| `1x.extra-small` | Development (default) | ~2 vCPU, 4GB | 4 m5.xlarge nodes |
| `1x.small` | Small production | ~4 vCPU, 8GB | 6+ m5.xlarge nodes |
| `1x.medium` | Medium production | ~8 vCPU, 16GB | 8+ m5.2xlarge nodes |

### Configuration

```hcl
# Development environment (default)
monitoring_loki_size = "1x.extra-small"

# Production environment
monitoring_loki_size = "1x.small"
```

### Resource Requirements

The `1x.small` LokiStack deploys multiple replicas for high availability:
- 2x Distributors
- 2x Queriers  
- 2x Query Frontends
- 2x Gateways
- 1x Compactor (StatefulSet)
- 1x Ingester (StatefulSet with PVC)
- 2x Index Gateways (StatefulSet with PVC)

**Warning:** If you see pods stuck in `Pending` state with "Insufficient cpu/memory" errors, your cluster doesn't have enough resources. Either:
1. Use a smaller LokiStack size (`1x.extra-small`)
2. Add more/larger worker nodes
3. Increase autoscaler max nodes

## Log Retention

Configure how long logs are retained:

```hcl
# Development: 7 days
monitoring_retention_days = 7

# Production: 30 days  
monitoring_retention_days = 30
```

This controls:
- Loki compactor retention (automatic deletion of old logs)
- S3 lifecycle rules (object expiration)
- Prometheus metric retention

## Prometheus Storage

Configure Prometheus persistent volume size:

```hcl
# Default: 100Gi
monitoring_prometheus_storage_size = "100Gi"

# Development (smaller)
monitoring_prometheus_storage_size = "50Gi"
```

## Storage Class

The storage class used for PVCs:

```hcl
# Default for ROSA
monitoring_storage_class = "gp3-csi"
```

## Destroying Clusters with Loki

When destroying a cluster with the monitoring layer enabled, the Loki S3 bucket 
may fail to delete because it contains log data. This is expected behavior to 
protect your data.

**S3 buckets are retained on `terraform destroy`** -- they are not deleted, to protect your
log data. During destroy, Terraform prints the bucket name and cleanup commands. When you
are ready to delete:

```bash
# Use the bucket name from the destroy output
BUCKET="dev-hcp-a3f7b2c1-loki-logs"

# Delete all objects and version markers
aws s3api delete-objects --bucket ${BUCKET} \
  --delete "$(aws s3api list-object-versions \
    --bucket ${BUCKET} \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# Then delete the empty bucket
aws s3 rb s3://${BUCKET}
```

**Note:** You can keep the bucket as long as needed. S3 lifecycle rules continue to
expire old data per the configured retention period.

## S3 Storage for Loki

Loki stores logs in S3 using STS/IRSA authentication (no static credentials).

The module automatically:
1. Creates an S3 bucket: `{cluster_name}-{random_8hex}-loki-logs`
2. Creates an IAM role with OIDC trust policy
3. Configures the Loki secret for STS authentication

### S3 Secret Format (STS Mode)

For STS/IRSA authentication, the secret must contain only:

```yaml
stringData:
  bucketnames: dev-hcp-a3f7b2c1-loki-logs
  region: us-east-1
  role_arn: arn:aws:iam::123456789:role/dev-hcp-loki
```

**Important:** Do NOT include `endpoint` or `access_key_*` fields - their presence forces static credential mode instead of STS.

### IAM Trust Policy

The IAM role trusts these service accounts (created by Loki Operator):

```json
{
  "Condition": {
    "StringEquals": {
      "${OIDC_PROVIDER}:sub": [
        "system:serviceaccount:openshift-logging:logging-loki",
        "system:serviceaccount:openshift-logging:logging-loki-ruler"
      ]
    }
  }
}
```

## Log Collection

The logging stack collects three types of logs and stores them in LokiStack:

| Log Type | Description | Source |
|----------|-------------|--------|
| **Application** | Logs from user workloads | Container stdout/stderr in non-system namespaces |
| **Infrastructure** | OpenShift system component logs | Pods in `openshift-*`, `kube-*`, `default` namespaces |
| **Audit** | API server and OAuth audit logs | Kubernetes API server, OAuth server |

### Viewing Logs in the Console

1. Navigate to **Observe → Logs** in the OpenShift Console
2. Select the log type from the dropdown (Application, Infrastructure, or Audit)
3. Use LogQL queries to filter:

```logql
# Application logs from a specific namespace
{log_type="application"} | kubernetes_namespace_name="my-app"

# Infrastructure logs with errors
{log_type="infrastructure"} |= "error"

# Audit logs for a specific user
{log_type="audit"} | json | user_username="admin"
```

### Log Collection Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                       OpenShift Cluster                        │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│   ┌──────────┐       ┌──────────┐       ┌──────────┐          │
│   │  Node 1  │       │  Node 2  │       │  Node N  │          │
│   │ ┌──────┐ │       │ ┌──────┐ │       │ ┌──────┐ │          │
│   │ │Vector│ │       │ │Vector│ │       │ │Vector│ │          │
│   │ └──┬───┘ │       │ └──┬───┘ │       │ └──┬───┘ │          │
│   └────┼─────┘       └────┼─────┘       └────┼─────┘          │
│        │                  │                  │                │
│        └──────────────────┼──────────────────┘                │
│                           ▼                                   │
│                   ┌───────────────┐                           │
│                   │   LokiStack   │                           │
│                   │  (Distributor │                           │
│                   │   Ingester    │                           │
│                   │   Querier)    │                           │
│                   └───────┬───────┘                           │
│                           │                                   │
└───────────────────────────┼───────────────────────────────────┘
                            ▼
                    ┌───────────────┐
                    │   S3 Bucket   │
                    │  (Long-term   │
                    │   storage)    │
                    └───────────────┘
```

### Time to First Logs

After enabling monitoring, expect:
- **Vector collectors**: Start within 2-3 minutes
- **First logs in Loki**: 5-10 minutes after collectors start
- **Console UI available**: After UIPlugin reconciles (~2-5 minutes)

If no logs appear after 15 minutes, check the troubleshooting section below.

## Cluster Observability Operator (COO)

COO provides the **Observe > Logs** page in the OpenShift Console.

### What COO Enables

- Log viewing with filters, queries, and time ranges
- Log expansion for detailed information
- Integration with log-based alerts from Loki ruler
- Links to correlated metrics

### UIPlugin Configuration

The UIPlugin connects the console to LokiStack:

```yaml
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
      namespace: openshift-logging
    logsLimit: 50
    timeout: 30s
```

## AlertManager Configuration

AlertManager is pre-configured by OpenShift for basic alerting. Custom receivers (email, Slack, PagerDuty) 
require manual configuration via the OpenShift Console or by creating AlertManager config resources.

See [OpenShift AlertManager documentation](https://docs.openshift.com/container-platform/latest/monitoring/managing-alerts.html) 
for configuring custom notification receivers.

## Classic vs HCP Cluster Differences

### PrometheusRules (HCP Only)

Custom PrometheusRules for monitoring stack health are **only deployed on HCP clusters**.

On Classic clusters, Red Hat SRE manages the `openshift-monitoring` namespace. The managed admission 
webhook rejects any custom PrometheusRules in that namespace with the error:
> "admission webhook denied the request: Prevented from accessing Red Hat managed resources"

This is a platform limitation, not a bug. On Classic clusters, rely on the built-in alerting rules 
provided by SRE, or create PrometheusRules in other namespaces for application-specific alerts.

## API Version and Requirements

**Minimum Supported Version**: OpenShift 4.16 with Cluster Logging Operator 6.x

This module uses the Observability API (`observability.openshift.io/v1`) which is available
starting with Cluster Logging Operator 6.0. The API provides a simplified deployment model:

| Component | API Group | Version |
|-----------|-----------|---------|
| LokiStack | `loki.grafana.com` | `v1` |
| ClusterLogForwarder | `observability.openshift.io` | `v1` |

### How It Works

The `ClusterLogForwarder` resource in the Observability API includes:

1. **Collector Configuration** - Deploys the Vector collector DaemonSet via the `collector` section
2. **Inputs** - Defines log sources (application, infrastructure, audit)
3. **Outputs** - Configures where logs are sent (LokiStack)
4. **Pipelines** - Routes inputs to outputs

The module also creates **ClusterRoleBindings** to grant the `logcollector` service account
permissions to collect each log type (application, infrastructure, audit).

## Troubleshooting

### LokiStack Pending

If LokiStack shows `PendingComponents`:

```bash
# Check pod status
oc get pods -n openshift-logging

# Check why pods are Pending
oc describe pod <pending-pod> -n openshift-logging

# Check PVC status
oc get pvc -n openshift-logging
```

Common causes:
1. **Insufficient resources** - Use smaller LokiStack size or add nodes
2. **PVC can't bind** - Check storage class exists
3. **Autoscaler at max** - Increase `autoscaler_max_replicas`

### S3 Authentication Errors

If Loki can't authenticate to S3:

```bash
# Check secret format (should NOT have 'endpoint' for STS)
oc get secret logging-loki-s3 -n openshift-logging -o yaml

# Check IAM role trust policy matches service accounts
aws iam get-role --role-name <cluster>-loki --query 'Role.AssumeRolePolicyDocument'

# Check Loki pod logs for STS errors
oc logs -n openshift-logging -l app.kubernetes.io/component=compactor | grep -i "sts\|credential\|error"
```

### Console Logs Not Loading

If Observe > Logs shows "cannot connect to LokiStack":

```bash
# Check UIPlugin status
oc get uiplugin logging -o yaml

# Check LokiStack is ready
oc get lokistack logging-loki -n openshift-logging

# Verify gateway is running
oc get pods -n openshift-logging -l app.kubernetes.io/component=lokistack-gateway
```

### No Logs / "No Datapoints Found"

If the Console shows no logs for any log type:

```bash
# 1. Check if Vector collector is running
oc get pods -n openshift-logging -l app.kubernetes.io/component=collector
# Should show pods on each node (DaemonSet)

# 2. Check ClusterLogForwarder exists and has status
oc get clusterlogforwarder instance -n openshift-logging -o yaml
# Look for conditions and status

# 3. Check ClusterRoleBindings for log collection
oc get clusterrolebinding | grep logcollector
# Should show: logcollector-collect-application-logs
#              logcollector-collect-infrastructure-logs  
#              logcollector-collect-audit-logs

# 4. Check Vector logs for errors
oc logs -n openshift-logging -l app.kubernetes.io/component=collector --tail=50
```

**Common causes:**
1. **Missing ClusterLogForwarder** - The collector DaemonSet deploys from this resource
2. **Missing RBAC** - Collector can't read logs without ClusterRoleBindings
3. **Operator still installing** - Re-run `terraform apply` after operators finish
4. **LokiStack not ready** - Collector has nowhere to send logs

### Recreating Monitoring Stack

To fully recreate the monitoring stack:

```bash
cd environments/commercial-hcp

# Delete existing resources
oc delete lokistack logging-loki -n openshift-logging
oc delete secret logging-loki-s3 -n openshift-logging
oc delete uiplugin logging
oc delete clusterlogforwarder instance -n openshift-logging
oc delete clusterrolebinding logcollector-collect-application-logs
oc delete clusterrolebinding logcollector-collect-infrastructure-logs
oc delete clusterrolebinding logcollector-collect-audit-logs

# Taint Terraform resources
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_loki_secret_direct[0]'
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_lokistack_direct[0]'
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_uiplugin_direct[0]'
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_logforwarder_direct[0]'
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_rbac_application_direct[0]'
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_rbac_infrastructure_direct[0]'
terraform taint -var-file=dev.tfvars 'module.gitops[0].null_resource.layer_monitoring_rbac_audit_direct[0]'

# Re-apply
terraform apply -var-file=dev.tfvars
```

## Example Configurations

### Development Environment

```hcl
# dev.tfvars
enable_layer_monitoring   = true
monitoring_loki_size      = "1x.extra-small"
monitoring_retention_days = 7
```

### Production Environment

```hcl
# prod.tfvars
enable_layer_monitoring            = true
monitoring_loki_size               = "1x.small"
monitoring_retention_days          = 30
monitoring_prometheus_storage_size = "100Gi"
```

## Related Documentation

- [Monitoring Layer README](../gitops-layers/layers/monitoring/README.md)
- [Loki Operator Documentation](https://loki-operator.dev/)
- [Red Hat OpenShift Logging](https://docs.openshift.com/container-platform/latest/logging/cluster-logging.html)
- [Cluster Observability Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/)
