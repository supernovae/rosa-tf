#------------------------------------------------------------------------------
# AutoNode Pool Module - Karpenter NodePool CRDs
#
# Creates Karpenter NodePool custom resources on the cluster. Each pool
# maps to a single NodePool CR with instance type, capacity type (spot /
# on-demand), labels, taints, and a nodeClassRef.
#
# NOTE: Karpenter restricts kubernetes.io and k8s.io domain labels in
# spec.template.metadata.labels. Use custom domains instead, e.g.:
#   node-role.autonode/gpu instead of node-role.kubernetes.io/gpu
#
# Prerequisites:
#   - AutoNode must be enabled on the cluster (rosa edit cluster --autonode=enabled)
#   - Karpenter CRDs must be present (~5 min after enabling AutoNode)
#   - kubectl provider must be configured with cluster auth
#------------------------------------------------------------------------------

locals {
  pool_map = { for pool in var.autonode_pools : pool.name => pool }

  # Karpenter rejects kubernetes.io and k8s.io domain labels in
  # spec.template.metadata.labels -- filter them out automatically.
  safe_template_labels = {
    for name, pool in local.pool_map : name => {
      for k, v in pool.labels : k => v
      if !can(regex("kubernetes\\.io|k8s\\.io", k))
    }
  }
}

resource "kubectl_manifest" "nodepool" {
  for_each = !var.skip_k8s_destroy ? local.pool_map : {}

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = each.value.name
      labels = merge(
        { "app.kubernetes.io/managed-by" = "terraform" },
        each.value.labels
      )
    }
    spec = {
      template = {
        metadata = {
          labels = local.safe_template_labels[each.key]
        }
        spec = merge(
          {
            requirements = [
              {
                key      = "node.kubernetes.io/instance-type"
                operator = "In"
                values   = [each.value.instance_type]
              },
              {
                key      = "karpenter.sh/capacity-type"
                operator = "In"
                values   = [each.value.capacity_type]
              }
            ]
            nodeClassRef = {
              group = var.node_class_group
              kind  = var.node_class_kind
              name  = each.value.node_class
            }
          },
          length(each.value.taints) > 0 ? {
            taints = [
              for t in each.value.taints : {
                key    = t.key
                value  = t.value
                effect = t.schedule_type
              }
            ]
          } : {}
        )
      }
    }
  })

  server_side_apply = true
  force_conflicts   = true
}
