#------------------------------------------------------------------------------
# Core GitOps Installation
#
# Installs the OpenShift GitOps operator (ArgoCD) and configures the
# foundation for all GitOps layers. Replaces the previous curl/shell-based
# approach with native Terraform resources.
#
# Resources managed:
#   1. openshift-gitops Namespace
#   2. GitOps Operator Subscription (OLM)
#   3. Cluster-admin RBAC for ArgoCD controller
#   4. ArgoCD instance with monitoring enabled
#   5. External repo Application (optional)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Step 1: Namespace
#
# Ensures the openshift-gitops namespace exists with our labels before the
# operator subscription is created. The GitOps operator also creates this
# namespace automatically, so Terraform's role is additive (labels + early creation).
#
# Uses kubectl_manifest instead of kubernetes_namespace_v1 because the native
# provider's delete state waiter treats "Active" as an unexpected state (rather
# than a pending state), causing it to error immediately at ~20s instead of
# waiting for the namespace to terminate. After the operator subscription is
# removed, OLM needs 1-3 minutes to finalize ClusterServiceVersion and
# OperatorGroup resources. kubectl_manifest handles this gracefully.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "openshift_gitops_ns" {
  count = var.skip_k8s_destroy ? 0 : 1

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: openshift-gitops
      labels:
        openshift.io/cluster-monitoring: "true"
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: rosa-gitops-layers
  YAML

  server_side_apply = true
  force_conflicts   = true

  # OLM needs time to clean up finalizer-bearing resources (CSV, OperatorGroup)
  # after the Subscription is removed. 5 minutes is ample.
  wait_for_rollout = false

  override_namespace = "openshift-gitops"
}

#------------------------------------------------------------------------------
# Step 2: GitOps Operator Subscription
#
# Installs OpenShift GitOps via OLM. The operator creates the ArgoCD CRD
# and deploys the default ArgoCD instance.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "gitops_subscription" {
  count = var.skip_k8s_destroy ? 0 : 1

  yaml_body = <<-YAML
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: openshift-gitops-operator
      namespace: openshift-operators
    spec:
      channel: ${local.operator_channels.gitops}
      installPlanApproval: Automatic
      name: openshift-gitops-operator
      source: redhat-operators
      sourceNamespace: openshift-marketplace
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.openshift_gitops_ns]
}

#------------------------------------------------------------------------------
# Step 3: Wait for Operator
#
# The GitOps operator needs time to install and create CRDs.
# Using time_sleep as a simple gate (kubectl_manifest wait_for requires
# the CRD to exist, which is what we're waiting for).
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_gitops_operator" {
  count = var.skip_k8s_destroy ? 0 : 1

  create_duration  = "120s"
  destroy_duration = "45s" # Give the operator time to clean up finalizers before namespace deletion

  depends_on = [kubectl_manifest.gitops_subscription]
}

#------------------------------------------------------------------------------
# Step 4: Cluster-admin RBAC for ArgoCD
#
# Grants the ArgoCD application controller cluster-admin access so it can
# manage resources across all namespaces.
#------------------------------------------------------------------------------

# ROSA's clusterrolebindings-validation webhook allows deletion of this CRB
# because openshift-gitops is in the webhook's exception list.
# See: https://github.com/openshift/managed-cluster-validating-webhooks/blob/master/pkg/webhooks/clusterrolebinding/clusterrolebinding.go
resource "kubectl_manifest" "argocd_rbac" {
  count = var.skip_k8s_destroy ? 0 : 1

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: openshift-gitops-argocd-rbac
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: rosa-gitops-layers
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: cluster-admin
    subjects:
      - kind: ServiceAccount
        name: openshift-gitops-argocd-application-controller
        namespace: openshift-gitops
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_gitops_operator]
}

#------------------------------------------------------------------------------
# Step 5: ArgoCD Instance
#
# Creates the ArgoCD instance with monitoring enabled. Uses kubectl_manifest
# because the ArgoCD CRD is installed by the operator (not built into K8s).
#------------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_instance" {
  count = var.skip_k8s_destroy ? 0 : 1

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1beta1
    kind: ArgoCD
    metadata:
      name: openshift-gitops
      namespace: openshift-gitops
    spec:
      monitoring:
        enabled: true
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
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    time_sleep.wait_for_gitops_operator,
    kubectl_manifest.argocd_rbac,
  ]
}

#------------------------------------------------------------------------------
# Step 6: Wait for ArgoCD to be ready
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_argocd_ready" {
  count = var.skip_k8s_destroy ? 0 : 1

  create_duration = "60s"

  depends_on = [kubectl_manifest.argocd_instance]
}

#------------------------------------------------------------------------------
# Step 7: External Repo Application (Optional)
#
# When a custom gitops_repo_url is provided, creates a single ArgoCD
# Application pointing at the user's repo. Users manage their own app
# structure within their repo.
#
# This creates a single Application (not an ApplicationSet).
#------------------------------------------------------------------------------

resource "kubectl_manifest" "external_repo_application" {
  count = !var.skip_k8s_destroy && local.has_custom_gitops_repo ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: custom-gitops
      namespace: openshift-gitops
      labels:
        app.kubernetes.io/part-of: rosa-gitops-layers
        app.kubernetes.io/component: custom-repo
        app.kubernetes.io/managed-by: terraform
    spec:
      project: default
      source:
        repoURL: ${var.gitops_repo_url}
        targetRevision: ${var.gitops_repo_revision}
        path: ${var.gitops_repo_path}
      destination:
        server: https://kubernetes.default.svc
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - PrunePropagationPolicy=foreground
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_argocd_ready]
}
