#!/bin/bash
#------------------------------------------------------------------------------
# GitOps Installation Script
#
# Called by Terraform null_resource to install OpenShift GitOps operator.
# Uses curl-based Kubernetes API calls with OAuth token authentication.
#
# Arguments:
#   $1 - API_URL: Cluster API URL (e.g., https://api.cluster.example.com:6443)
#   $2 - TOKEN: OAuth bearer token for authentication
#   $3 - ACTION: One of: validate, namespace, subscription, configmap, rbac, argocd, appset
#   $4+ - Additional arguments depending on action
#------------------------------------------------------------------------------

set -e

API_URL="$1"
TOKEN="$2"
ACTION="$3"

# Standard headers
HEADERS="-H 'Authorization: Bearer $TOKEN' -H 'Content-Type: application/yaml' -H 'Accept: application/yaml'"

# Function to make API call and report result
api_call() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local description="$4"
  
  echo ">>> $description"
  
  if [ -n "$data" ]; then
    RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/yaml" \
      -H "Accept: application/yaml" \
      -X "$method" "$API_URL$endpoint" \
      -d "$data" 2>&1)
  else
    RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/yaml" \
      -X "$method" "$API_URL$endpoint" 2>&1)
  fi
  
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")
  
  echo "HTTP Status: $HTTP_CODE"
  
  case "$HTTP_CODE" in
    200|201)
      echo "SUCCESS"
      return 0
      ;;
    409)
      echo "OK (already exists)"
      return 0
      ;;
    401|403)
      echo "ERROR: Authentication failed"
      echo "$BODY" | head -5
      return 1
      ;;
    "")
      echo "ERROR: No response - cluster may be unreachable"
      return 1
      ;;
    *)
      echo "ERROR: Unexpected response"
      echo "$BODY" | head -10
      return 1
      ;;
  esac
}

case "$ACTION" in
  validate)
    echo "============================================="
    echo "GitOps Installation - Connectivity Check"
    echo "============================================="
    echo ""
    echo "API URL: $API_URL"
    echo "Token length: ${#TOKEN}"
    echo ""
    
    if [ -z "$TOKEN" ]; then
      echo "ERROR: Token is empty!"
      echo ""
      echo "This usually means cluster_auth module failed."
      echo "Check cluster_auth_summary output for details."
      exit 1
    fi
    
    api_call "GET" "/api/v1/namespaces/default" "" "Testing API connectivity"
    ;;
    
  namespace)
    api_call "POST" "/api/v1/namespaces" '
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops
  labels:
    openshift.io/cluster-monitoring: "true"
' "Creating openshift-gitops namespace"
    ;;
    
  subscription)
    api_call "POST" "/apis/operators.coreos.com/v1alpha1/namespaces/openshift-operators/subscriptions" '
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
' "Creating GitOps operator subscription"
    ;;
    
  rbac)
    api_call "POST" "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings" '
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-gitops-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
' "Creating cluster-admin RBAC for ArgoCD"
    ;;
    
  wait-crd)
    echo "Waiting for ArgoCD CRD to be available..."
    for i in $(seq 1 30); do
      if curl -sk -H "Authorization: Bearer $TOKEN" "$API_URL/apis/argoproj.io/v1beta1" 2>/dev/null | grep -q "ArgoCD"; then
        echo "ArgoCD CRD is ready"
        exit 0
      fi
      echo "Waiting... ($i/30)"
      sleep 10
    done
    echo "WARNING: ArgoCD CRD not ready after 5 minutes"
    exit 0
    ;;
    
  argocd)
    api_call "POST" "/apis/argoproj.io/v1beta1/namespaces/openshift-gitops/argocds" '
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  controller:
    processors: {}
    resources:
      limits:
        cpu: "2"
        memory: 2Gi
      requests:
        cpu: 250m
        memory: 1Gi
    sharding: {}
  ha:
    enabled: false
  redis:
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  repo:
    resources:
      limits:
        cpu: "1"
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 256Mi
  server:
    autoscale:
      enabled: false
    route:
      enabled: true
      tls:
        termination: reencrypt
        insecureEdgeTerminationPolicy: Redirect
    service:
      type: ClusterIP
  applicationSet:
    resources:
      limits:
        cpu: "2"
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 512Mi
  rbac:
    defaultPolicy: ""
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
    scopes: "[groups]"
  sso:
    provider: dex
    dex:
      openShiftOAuth: true
' "Creating ArgoCD instance"
    ;;
    
  configmap)
    # ConfigMap data is passed as argument 4
    CONFIGMAP_DATA="$4"
    api_call "POST" "/api/v1/namespaces/openshift-gitops/configmaps" "$CONFIGMAP_DATA" "Creating rosa-gitops-config ConfigMap"
    ;;
    
  appset)
    # ApplicationSet YAML is passed as argument 4
    APPSET_DATA="$4"
    api_call "POST" "/apis/argoproj.io/v1alpha1/namespaces/openshift-gitops/applicationsets" "$APPSET_DATA" "Creating rosa-layers ApplicationSet"
    ;;

  #------------------------------------------------------------------------------
  # Generic YAML Application (DRY approach)
  #
  # Reads YAML from gitops-layers/layers/ directory via Terraform file()
  # and applies to the appropriate Kubernetes API endpoint.
  #------------------------------------------------------------------------------

  apply-yaml)
    # Generic YAML application
    # Args: $4=description, $5=api_endpoint, $6+=yaml_content (rest of args)
    DESCRIPTION="$4"
    API_ENDPOINT="$5"
    shift 5
    YAML_CONTENT="$*"
    
    echo "============================================="
    echo "Applying: $DESCRIPTION"
    echo "============================================="
    
    api_call "POST" "$API_ENDPOINT" "$YAML_CONTENT" "$DESCRIPTION"
    ;;

  apply-yaml-optional)
    # Best-effort YAML application - doesn't fail if CRD not ready (404)
    # Use for resources that depend on slow-installing operators
    # Args: $4=description, $5=api_endpoint, $6+=yaml_content (rest of args)
    DESCRIPTION="$4"
    API_ENDPOINT="$5"
    shift 5
    YAML_CONTENT="$*"
    
    echo "============================================="
    echo "Applying (optional): $DESCRIPTION"
    echo "============================================="
    
    # Temporarily disable exit-on-error for this call
    set +e
    
    echo ">>> $DESCRIPTION"
    RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/yaml" \
      -H "Accept: application/yaml" \
      -X "POST" "$API_URL$API_ENDPOINT" \
      -d "$YAML_CONTENT" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")
    
    echo "HTTP Status: $HTTP_CODE"
    
    case "$HTTP_CODE" in
      200|201)
        echo "SUCCESS"
        ;;
      409)
        echo "OK (already exists)"
        ;;
      404)
        echo "SKIPPED: CRD not ready yet (operator still installing)"
        echo "Re-run 'terraform apply' after operator finishes installing."
        echo ""
        echo "To check operator status:"
        echo "  oc get csv -n openshift-logging"
        echo "  oc get crd | grep logging"
        ;;
      401|403)
        echo "ERROR: Authentication failed"
        echo "$BODY" | head -5
        set -e
        exit 1
        ;;
      "")
        echo "ERROR: No response - cluster may be unreachable"
        set -e
        exit 1
        ;;
      *)
        echo "WARNING: Unexpected response (continuing anyway)"
        echo "$BODY" | head -5
        ;;
    esac
    
    set -e
    ;;

  wait-operator)
    # Wait for an operator CRD to be available
    # Args: $4=api_group (e.g., oadp.openshift.io), $5=version, $6=kind
    API_GROUP="$4"
    VERSION="$5"
    KIND="$6"
    MAX_ATTEMPTS=36  # 36 * 10s = 6 minutes max wait
    
    echo "============================================="
    echo "Waiting for Operator CRD"
    echo "============================================="
    echo "API Group: $API_GROUP"
    echo "Version: $VERSION"
    echo "Kind: $KIND"
    echo ""
    
    for i in $(seq 1 $MAX_ATTEMPTS); do
      # Check if the API group/version is available
      RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "$API_URL/apis/$API_GROUP/$VERSION" 2>&1)
      
      HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
      BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")
      
      if [ "$HTTP_CODE" = "200" ]; then
        # Check if the specific kind is in the response
        if echo "$BODY" | grep -qi "\"kind\":.*\"$KIND\""; then
          echo "SUCCESS: $KIND CRD is ready (attempt $i)"
          exit 0
        fi
        # Also check resources list
        if echo "$BODY" | grep -qi "\"name\":.*\"${KIND,,}s\""; then
          echo "SUCCESS: $KIND CRD is ready (attempt $i)"
          exit 0
        fi
        # Check lowercase plural form in resources
        KIND_LOWER=$(echo "$KIND" | tr '[:upper:]' '[:lower:]')
        if echo "$BODY" | grep -qi "\"name\":.*\"${KIND_LOWER}"; then
          echo "SUCCESS: $KIND CRD is ready (attempt $i)"
          exit 0
        fi
      fi
      
      echo "Waiting for $KIND CRD... (attempt $i/$MAX_ATTEMPTS, HTTP: $HTTP_CODE)"
      sleep 10
    done
    
    echo "ERROR: $KIND CRD not ready after $MAX_ATTEMPTS attempts"
    echo "The operator may still be installing. Check:"
    echo "  oc get csv -n openshift-adp"
    echo "  oc get crd | grep $API_GROUP"
    exit 1
    ;;
    
  *)
    echo "Unknown action: $ACTION"
    echo "Valid actions: validate, namespace, subscription, rbac, wait-crd, argocd, configmap, appset, apply-yaml, apply-yaml-optional, wait-operator"
    exit 1
    ;;
esac
