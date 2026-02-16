#------------------------------------------------------------------------------
# Terraform Operator Identity
#
# Creates a dedicated namespace, ServiceAccount, ClusterRoleBinding, and
# long-lived token for Terraform to use when managing cluster resources.
#
# The SA lives in a dedicated namespace (default: rosa-terraform) rather than
# kube-system to avoid ROSA's managed admission webhooks that block deletion
# of resources in system namespaces. This allows full Terraform lifecycle
# management: create, update, rotate, and destroy.
#
# Audit identity in OpenShift API server logs:
#   user: system:serviceaccount:rosa-terraform:<sa-name>
#   user-agent: Terraform/<version>
#
# BOOTSTRAP FLOW:
#   1. First apply: OAuth token from cluster_auth bootstraps the providers
#   2. SA + token created, token stored in state (sensitive)
#   3. User copies output to gitops_cluster_token in tfvars
#   4. Subsequent applies: SA token used directly, no OAuth needed
#   5. htpasswd IDP can optionally be removed (create_admin_user = false)
#
# DESTROY FLOW:
#   All resources (SA, Secret, namespace, CRBs) are fully deletable.
#   ROSA's clusterrolebindings-validation webhook allows deletion because:
#     - rosa-terraform namespace does NOT match the protected regex (^openshift-.*|kube-system)
#     - openshift-gitops IS in the webhook's exception list
#     - system: prefixed users (our SA) bypass the webhook entirely
#   See: https://github.com/openshift/managed-cluster-validating-webhooks/blob/master/pkg/webhooks/clusterrolebinding/clusterrolebinding.go
#
# LEAST PRIVILEGE NOTE:
#   The SA requires cluster-admin because it installs operators, creates
#   namespaces, manages CRDs, and configures cluster-scoped resources
#   across all GitOps layers. This is equivalent to what the previous
#   OAuth admin token required.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Dedicated namespace for the Terraform operator identity.
# Avoids kube-system where ROSA's serviceaccount-validation webhook blocks
# deletion. This namespace is fully managed by Terraform.
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "terraform_operator_ns" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name = var.terraform_sa_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "gitops-operator"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

#------------------------------------------------------------------------------
# ServiceAccount for Terraform cluster management.
#------------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "terraform_operator" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name      = var.terraform_sa_name
    namespace = var.terraform_sa_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "gitops-operator"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
    }

    annotations = {
      "rosa-tf/purpose"     = "Automated cluster management by Terraform"
      "rosa-tf/rotate-with" = "terraform apply -replace=kubernetes_secret_v1.terraform_operator_token"
    }
  }

  depends_on = [kubernetes_namespace_v1.terraform_operator_ns]
}

#------------------------------------------------------------------------------
# ClusterRoleBinding: grants the SA cluster-admin.
#
# CRBs are cluster-scoped. ROSA's clusterrolebindings-validation webhook
# allows deletion of this CRB because the subject SA is in rosa-terraform,
# which does NOT match the protected namespace regex (^openshift-.*|kube-system).
# Additionally, Terraform authenticates as system:serviceaccount:rosa-terraform:*
# which bypasses the webhook entirely (all system: users are allowed).
#
# The CRB never needs rotation -- only the SA token does.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "terraform_operator_crb" {
  count = var.skip_k8s_destroy ? 0 : 1

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: ${var.terraform_sa_name}-rbac
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: gitops-operator
        app.kubernetes.io/part-of: rosa-gitops-layers
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: cluster-admin
    subjects:
      - kind: ServiceAccount
        name: ${var.terraform_sa_name}
        namespace: ${var.terraform_sa_namespace}
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubernetes_service_account_v1.terraform_operator]
}

#------------------------------------------------------------------------------
# Long-lived SA token (Kubernetes 1.24+ pattern).
#
# Creates a Secret of type kubernetes.io/service-account-token which is
# automatically populated with a JWT by the token controller.
#
# The token is stored in Terraform state (sensitive). To rotate:
#   terraform apply -replace="module.gitops[0].kubernetes_secret_v1.terraform_operator_token[0]"
# This deletes the old secret (immediately invalidating the token) and creates
# a new one in a single apply.
#------------------------------------------------------------------------------

resource "kubernetes_secret_v1" "terraform_operator_token" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name      = "${var.terraform_sa_name}-token"
    namespace = var.terraform_sa_namespace

    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.terraform_operator[0].metadata[0].name
    }

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "gitops-operator"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
    }
  }

  type = "kubernetes.io/service-account-token"

  # Wait for the token controller to populate the token data
  wait_for_service_account_token = true
}
