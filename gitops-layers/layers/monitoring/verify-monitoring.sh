#!/bin/bash
#------------------------------------------------------------------------------
# Monitoring Stack Verification Script
#
# This script verifies that the monitoring and logging stack is properly
# configured and functioning. Run this after deploying the monitoring layer.
#
# Usage:
#   ./verify-monitoring.sh [--verbose]
#
# Prerequisites:
#   - oc CLI logged into the cluster
#   - Monitoring layer deployed
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#------------------------------------------------------------------------------

set -euo pipefail

VERBOSE="${1:-}"
FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    FAILED=1
}

log_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

verbose() {
    if [[ "$VERBOSE" == "--verbose" ]]; then
        echo "$1"
    fi
}

#------------------------------------------------------------------------------
# Task 1: Verify Prometheus Storage Binding
#------------------------------------------------------------------------------
verify_prometheus_storage() {
    log_section "Task 1: Prometheus Storage Verification"
    
    echo "Checking prometheus-k8s PVC status..."
    
    # Get PVC status
    PVC_STATUS=$(oc get pvc -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
    
    if [[ -z "$PVC_STATUS" ]]; then
        log_error "No Prometheus PVCs found. cluster-monitoring-config may not be applied."
        return
    fi
    
    # Check if all PVCs are bound
    BOUND_COUNT=$(echo "$PVC_STATUS" | tr ' ' '\n' | grep -c "Bound" || echo "0")
    TOTAL_COUNT=$(echo "$PVC_STATUS" | tr ' ' '\n' | wc -w | tr -d ' ')
    
    if [[ "$BOUND_COUNT" == "$TOTAL_COUNT" ]]; then
        log_info "All Prometheus PVCs are Bound ($BOUND_COUNT/$TOTAL_COUNT)"
    else
        log_error "Not all Prometheus PVCs are Bound ($BOUND_COUNT/$TOTAL_COUNT)"
    fi
    
    # Check storage class
    STORAGE_CLASS=$(oc get pvc -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.storageClassName}' 2>/dev/null || echo "")
    if [[ -n "$STORAGE_CLASS" ]]; then
        log_info "Storage class: $STORAGE_CLASS"
    fi
    
    # Check pod status
    echo ""
    echo "Checking prometheus-k8s pod status..."
    POD_STATUS=$(oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
    
    RUNNING_COUNT=$(echo "$POD_STATUS" | tr ' ' '\n' | grep -c "Running" || echo "0")
    POD_TOTAL=$(echo "$POD_STATUS" | tr ' ' '\n' | wc -w | tr -d ' ')
    
    if [[ "$RUNNING_COUNT" == "$POD_TOTAL" ]] && [[ "$POD_TOTAL" -gt 0 ]]; then
        log_info "All Prometheus pods are Running ($RUNNING_COUNT/$POD_TOTAL)"
    else
        log_error "Not all Prometheus pods are Running ($RUNNING_COUNT/$POD_TOTAL)"
    fi
    
    verbose "$(oc get pvc -n openshift-monitoring -l app.kubernetes.io/name=prometheus)"
}

#------------------------------------------------------------------------------
# Task 2: Verify Loki STS Role Assumption
#------------------------------------------------------------------------------
verify_loki_sts() {
    log_section "Task 2: Loki STS Role Verification"
    
    echo "Checking Loki service account annotations..."
    
    # Check if LokiStack exists
    LOKISTACK=$(oc get lokistack -n openshift-logging logging-loki -o name 2>/dev/null || echo "")
    
    if [[ -z "$LOKISTACK" ]]; then
        log_warn "LokiStack 'logging-loki' not found. Logging may not be deployed yet."
        return
    fi
    
    log_info "LokiStack 'logging-loki' exists"
    
    # Check S3 secret
    echo ""
    echo "Checking S3 credentials secret..."
    S3_SECRET=$(oc get secret -n openshift-logging logging-loki-s3 -o name 2>/dev/null || echo "")
    
    if [[ -z "$S3_SECRET" ]]; then
        log_error "S3 credentials secret 'logging-loki-s3' not found"
        return
    fi
    
    # Check role_arn in secret
    ROLE_ARN=$(oc get secret -n openshift-logging logging-loki-s3 -o jsonpath='{.data.role_arn}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$ROLE_ARN" ]]; then
        log_info "IAM Role ARN configured: $ROLE_ARN"
    else
        log_error "role_arn not found in S3 secret"
    fi
    
    # Check Loki pods for STS errors
    echo ""
    echo "Checking Loki pods for STS errors..."
    
    STS_ERRORS=$(oc logs -n openshift-logging -l app.kubernetes.io/component=ingester --tail=50 2>/dev/null | grep -i "sts\|assume\|credential" | grep -i "error\|fail" | head -5 || echo "")
    
    if [[ -z "$STS_ERRORS" ]]; then
        log_info "No STS errors found in Loki ingester logs"
    else
        log_error "STS errors found in Loki logs:"
        echo "$STS_ERRORS"
    fi
    
    # Verify pods can access S3
    echo ""
    echo "Checking Loki component status..."
    
    for component in distributor ingester querier compactor; do
        POD_READY=$(oc get pods -n openshift-logging -l app.kubernetes.io/component=$component -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [[ "$POD_READY" == "True" ]]; then
            log_info "Loki $component is Ready"
        else
            log_warn "Loki $component is not Ready"
        fi
    done
}

#------------------------------------------------------------------------------
# Task 3: Verify Retention Policy
#------------------------------------------------------------------------------
verify_retention() {
    log_section "Task 3: Retention Policy Verification"
    
    # Check Prometheus retention
    echo "Checking Prometheus retention configuration..."
    
    PROM_RETENTION=$(oc get prometheus -n openshift-monitoring k8s -o jsonpath='{.spec.retention}' 2>/dev/null || echo "")
    
    if [[ -n "$PROM_RETENTION" ]]; then
        log_info "Prometheus retention: $PROM_RETENTION"
    else
        log_warn "Prometheus retention not explicitly set (using default)"
    fi
    
    # Check Loki retention via compactor
    echo ""
    echo "Checking Loki compactor retention status..."
    
    LOKISTACK_RETENTION=$(oc get lokistack -n openshift-logging logging-loki -o jsonpath='{.spec.limits.global.retention.days}' 2>/dev/null || echo "")
    
    if [[ -n "$LOKISTACK_RETENTION" ]]; then
        log_info "LokiStack retention: ${LOKISTACK_RETENTION} days"
    else
        log_warn "LokiStack retention not found in spec"
    fi
    
    # Check compactor is running
    COMPACTOR_READY=$(oc get pods -n openshift-logging -l app.kubernetes.io/component=compactor -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    
    if [[ "$COMPACTOR_READY" == "True" ]]; then
        log_info "Loki compactor is running (enforces retention)"
    else
        log_warn "Loki compactor is not ready (retention may not be enforced)"
    fi
    
    # Check compactor logs for retention activity
    echo ""
    echo "Checking compactor retention activity..."
    
    RETENTION_ACTIVITY=$(oc logs -n openshift-logging -l app.kubernetes.io/component=compactor --tail=100 2>/dev/null | grep -i "retention\|delete\|compact" | tail -3 || echo "")
    
    if [[ -n "$RETENTION_ACTIVITY" ]]; then
        log_info "Compactor retention activity detected"
        verbose "$RETENTION_ACTIVITY"
    else
        log_info "No recent retention activity (normal if logs are fresh)"
    fi
}

#------------------------------------------------------------------------------
# Task 4: Verify Metric Scraping
#------------------------------------------------------------------------------
verify_metrics() {
    log_section "Task 4: Metric Scraping Verification"
    
    echo "Checking ServiceMonitor for Loki components..."
    
    # Check if ServiceMonitors exist
    LOKI_SM=$(oc get servicemonitor -n openshift-logging -o name 2>/dev/null | wc -l | tr -d ' ')
    
    if [[ "$LOKI_SM" -gt 0 ]]; then
        log_info "Found $LOKI_SM ServiceMonitor(s) in openshift-logging"
    else
        log_warn "No ServiceMonitors found in openshift-logging"
    fi
    
    # Check Vector collector metrics
    echo ""
    echo "Checking Vector collector metrics..."
    
    COLLECTOR_SM=$(oc get servicemonitor -n openshift-logging collector-metrics -o name 2>/dev/null || echo "")
    
    if [[ -n "$COLLECTOR_SM" ]]; then
        log_info "Vector collector ServiceMonitor exists"
    else
        log_warn "Vector collector ServiceMonitor not found"
    fi
    
    # Check if Prometheus is scraping Loki targets
    echo ""
    echo "Checking Prometheus targets for Loki..."
    
    # This requires port-forwarding to Prometheus, so we check via API
    TARGETS_UP=$(oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | grep -c "openshift-logging" || echo "0")
    
    if [[ "$TARGETS_UP" -gt 0 ]]; then
        log_info "Prometheus is scraping $TARGETS_UP target(s) from openshift-logging"
    else
        log_warn "No Prometheus targets found for openshift-logging"
    fi
}

#------------------------------------------------------------------------------
# Task 5: Verify Log Forwarding
#------------------------------------------------------------------------------
verify_log_forwarding() {
    log_section "Task 5: Log Forwarding Verification"
    
    echo "Checking ClusterLogForwarder status..."
    
    # Check CLF exists
    CLF=$(oc get clusterlogforwarder -n openshift-logging instance -o name 2>/dev/null || echo "")
    
    if [[ -z "$CLF" ]]; then
        log_warn "ClusterLogForwarder 'instance' not found"
        return
    fi
    
    log_info "ClusterLogForwarder 'instance' exists"
    
    # Check CLF conditions
    CLF_READY=$(oc get clusterlogforwarder -n openshift-logging instance -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    
    if [[ "$CLF_READY" == "True" ]]; then
        log_info "ClusterLogForwarder is Ready"
    else
        log_warn "ClusterLogForwarder is not Ready"
        CLF_MESSAGE=$(oc get clusterlogforwarder -n openshift-logging instance -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
        if [[ -n "$CLF_MESSAGE" ]]; then
            echo "  Message: $CLF_MESSAGE"
        fi
    fi
    
    # Check Vector collector DaemonSet
    echo ""
    echo "Checking Vector collector DaemonSet..."
    
    DESIRED=$(oc get ds -n openshift-logging collector -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    READY=$(oc get ds -n openshift-logging collector -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    
    if [[ "$DESIRED" == "$READY" ]] && [[ "$DESIRED" -gt 0 ]]; then
        log_info "Vector collector DaemonSet: $READY/$DESIRED pods ready"
    else
        log_error "Vector collector DaemonSet: $READY/$DESIRED pods ready"
    fi
    
    # Check for recent log ingestion
    echo ""
    echo "Checking recent log ingestion..."
    
    INGESTION_RATE=$(oc exec -n openshift-logging -l app.kubernetes.io/component=distributor -- wget -qO- 'http://localhost:3100/metrics' 2>/dev/null | grep "loki_distributor_lines_received_total" | tail -1 || echo "")
    
    if [[ -n "$INGESTION_RATE" ]]; then
        log_info "Loki is receiving logs"
        verbose "$INGESTION_RATE"
    else
        log_warn "Could not verify log ingestion rate"
    fi
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
print_summary() {
    log_section "Summary"
    
    if [[ "$FAILED" -eq 0 ]]; then
        echo -e "${GREEN}All verification checks passed!${NC}"
        echo ""
        echo "Your monitoring stack is properly configured."
    else
        echo -e "${RED}Some verification checks failed.${NC}"
        echo ""
        echo "Review the errors above and check:"
        echo "  - cluster-monitoring-config ConfigMap in openshift-monitoring"
        echo "  - LokiStack and ClusterLogForwarder in openshift-logging"
        echo "  - IAM role and S3 bucket permissions"
        echo ""
        echo "Useful commands:"
        echo "  oc get pods -n openshift-monitoring"
        echo "  oc get pods -n openshift-logging"
        echo "  oc logs -n openshift-logging -l app.kubernetes.io/component=ingester"
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ROSA Monitoring Stack Verification"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Verify oc is logged in
    if ! oc whoami &>/dev/null; then
        log_error "Not logged into OpenShift cluster. Run 'oc login' first."
        exit 1
    fi
    
    CLUSTER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
    echo "Cluster: $CLUSTER"
    echo ""
    
    verify_prometheus_storage
    verify_loki_sts
    verify_retention
    verify_metrics
    verify_log_forwarding
    print_summary
    
    exit $FAILED
}

main "$@"
