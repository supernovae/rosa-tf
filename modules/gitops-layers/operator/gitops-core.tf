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
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "openshift_gitops" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name = "openshift-gitops"

    labels = {
      "openshift.io/cluster-monitoring"  = "true"
      "app.kubernetes.io/managed-by"     = "terraform"
      "app.kubernetes.io/part-of"        = "rosa-gitops-layers"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels["olm.operatorgroup.uid/"],
    ]
  }
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

  depends_on = [kubernetes_namespace_v1.openshift_gitops]
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
  destroy_duration = "30s" # Give the operator time to clean up finalizers before namespace deletion

  depends_on = [kubectl_manifest.gitops_subscription]
}

#------------------------------------------------------------------------------
# Step 4: Cluster-admin RBAC for ArgoCD
#
# Grants the ArgoCD application controller cluster-admin access so it can
# manage resources across all namespaces.
#------------------------------------------------------------------------------

# ROSA's managed admission webhook blocks deletion of CRBs binding to cluster-admin.
# prevent_destroy stops Terraform from attempting the delete. The CRB dies with the cluster.
#
# Before full cluster destroy:
#   terraform state rm 'module.gitops[0].kubectl_manifest.argocd_rbac[0]'
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

  lifecycle {
    prevent_destroy = true
  }

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
