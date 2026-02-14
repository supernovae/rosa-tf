#------------------------------------------------------------------------------
# Terraform Operator Identity
#
# Creates a Kubernetes ServiceAccount for Terraform to use when managing
# cluster resources. This replaces the OAuth-based authentication with a
# persistent, non-human identity that:
#
# - Uses native Kubernetes RBAC (no OAuth, no cached credentials)
# - Token stored only in Terraform state (encrypted S3 at rest)
# - Identifiable in OpenShift API audit logs as:
#     user: system:serviceaccount:kube-system:<sa-name>
#     user-agent: Terraform/<version>
# - Rotatable via: terraform apply -replace="module.gitops[0].kubernetes_secret_v1.terraform_operator_token"
#
# BOOTSTRAP FLOW:
#   1. First apply: OAuth token from cluster_auth bootstraps the providers
#   2. SA + token created, token stored in state (sensitive)
#   3. User copies output to gitops_cluster_token in tfvars
#   4. Subsequent applies: SA token used directly, no OAuth needed
#   5. htpasswd IDP can optionally be removed (create_admin_user = false)
#
# LEAST PRIVILEGE NOTE:
#   The SA requires cluster-admin because it installs operators, creates
#   namespaces, manages CRDs, and configures cluster-scoped resources
#   across all GitOps layers. This is equivalent to what the previous
#   OAuth admin token required.
#------------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "terraform_operator" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name      = var.terraform_sa_name
    namespace = "kube-system"

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
}

resource "kubernetes_cluster_role_binding_v1" "terraform_operator" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name = "${var.terraform_sa_name}-cluster-admin"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "gitops-operator"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.terraform_operator[0].metadata[0].name
    namespace = "kube-system"
  }
}

# Long-lived SA token (Kubernetes 1.24+ pattern).
# Creates a Secret of type kubernetes.io/service-account-token which is
# automatically populated with a JWT by the token controller.
#
# The token is stored in Terraform state (sensitive). To rotate:
#   terraform apply -replace="module.gitops[0].kubernetes_secret_v1.terraform_operator_token"
# This deletes the old secret (immediately invalidating the token) and creates
# a new one in a single apply.
resource "kubernetes_secret_v1" "terraform_operator_token" {
  count = var.skip_k8s_destroy ? 0 : 1

  metadata {
    name      = "${var.terraform_sa_name}-token"
    namespace = "kube-system"

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
