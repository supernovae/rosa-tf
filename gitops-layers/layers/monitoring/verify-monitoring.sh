#!/usr/bin/env bash
# Read-only readiness checks. Does not prove ingestion, queries, or notification
# delivery: complete the end-to-end acceptance test in docs/OBSERVABILITY.md.
# Functions are invoked indirectly by check().
# shellcheck disable=SC2329
set -euo pipefail
for tool in oc jq; do
    command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }
done
oc whoami >/dev/null
failed=0
check() {
    local label="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$label"
    else
        printf 'FAIL: %s\n' "$label" >&2
        failed=1
    fi
}
subscription_ready() {
    local namespace="$1" subscription="$2" csv
    csv=$(oc -n "$namespace" get subscription "$subscription" -o jsonpath='{.status.installedCSV}') || return 1
    [[ -n "$csv" ]] || return 1
    oc -n "$namespace" get csv "$csv" -o json | jq -e '.status.phase == "Succeeded"' >/dev/null
}
pods_ready() {
    oc -n "$1" get pods -o json | jq -e '
      [.items[] | select(.status.phase != "Succeeded")] |
      length > 0 and all(.[];
        any(.status.conditions[]?; .type == "Ready" and .status == "True"))
    ' >/dev/null
}
pvcs_bound() {
    oc -n "$1" get pvc -o json | jq -e '
      .items | length > 0 and all(.[]; .status.phase == "Bound")
    ' >/dev/null
}
collectors_ready() {
    local uid
    uid=$(oc -n openshift-logging get clusterlogforwarder.observability.openshift.io instance -o jsonpath='{.metadata.uid}') || return 1
    oc -n openshift-logging get daemonsets -o json | jq -e --arg uid "$uid" '
      [.items[] | select(any(.metadata.ownerReferences[]?; .uid == $uid))] |
      length > 0 and all(.[];
        .status.observedGeneration >= .metadata.generation and
        .status.desiredNumberScheduled > 0 and
        .status.numberReady == .status.desiredNumberScheduled and
        .status.updatedNumberScheduled == .status.desiredNumberScheduled)
    ' >/dev/null
}
check "Loki operator" subscription_ready openshift-operators-redhat loki-operator
check "Logging operator" subscription_ready openshift-logging cluster-logging
check "Cluster Observability Operator" subscription_ready openshift-operators cluster-observability-operator
check "LokiStack Ready" oc -n openshift-logging wait lokistack/logging-loki --for=condition=Ready --timeout=30s
check "ClusterLogForwarder Ready" oc -n openshift-logging wait clusterlogforwarder.observability.openshift.io/instance --for=condition=Ready --timeout=30s
check "Collectors on all eligible nodes" collectors_ready
check "All logging pods Ready" pods_ready openshift-logging
check "Logging PVCs Bound" pvcs_bound openshift-logging
check "User-workload monitoring pods Ready" pods_ready openshift-user-workload-monitoring
check "User-workload PVCs Bound" pvcs_bound openshift-user-workload-monitoring
check "Logging console plugin exists" oc get uiplugin logging -o name
if [[ "$failed" -eq 0 ]]; then
    echo "Readiness checks passed. Now verify a fresh log, up metric, dashboard, and delivered test alert."
fi
exit "$failed"
