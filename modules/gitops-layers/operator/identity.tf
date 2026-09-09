# Privileged infrastructure-runner identity, separate from Argo CD workloads.
# Prefer short-lived TokenRequest credentials supplied outside Terraform state.
# Permanent token Secrets are legacy opt-in only. See docs/GITOPS.md for migration.
# The runner needs platform-level privileges for operator/layer resources; never
# delegate this identity to application pods or untrusted PR jobs.

resource "kubernetes_namespace_v1" "terraform_operator_ns" {
  count = 1

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
  count                           = 1
  automount_service_account_token = false

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
      "rosa-tf/credentials" = "Prefer short-lived TokenRequest credentials; see docs/GITOPS.md"
    }
  }

  depends_on = [kubernetes_namespace_v1.terraform_operator_ns]
}

#------------------------------------------------------------------------------
# ClusterRoleBinding: grants the SA cluster-admin.
#
# Cluster-scoped grants belong to the reviewed infrastructure runner only.
# Verify current ROSA admission and independent credentials before teardown;
# do not rely on assumptions about service-account webhook exemptions.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "terraform_operator_crb" {
  count = 1

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
  force_conflicts   = false

  depends_on = [kubernetes_service_account_v1.terraform_operator]
}
