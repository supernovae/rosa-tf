#------------------------------------------------------------------------------
# Layer: Web Terminal
#
# Installs the OpenShift Web Terminal operator which provides a browser-based
# terminal in the OpenShift console with pre-installed CLI tools.
#
# Dependencies: None (operator-only layer)
# Terraform Resources: None required
#------------------------------------------------------------------------------

resource "kubectl_manifest" "terminal_subscription" {
  count = !var.skip_k8s_destroy && var.enable_layer_terminal ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: web-terminal
      namespace: openshift-operators
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: rosa-gitops-layers
        app.kubernetes.io/component: terminal
    spec:
      channel: ${local.operator_channels.web_terminal}
      name: web-terminal
      source: redhat-operators
      sourceNamespace: openshift-marketplace
      installPlanApproval: Automatic
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [time_sleep.wait_for_argocd_ready]
}
