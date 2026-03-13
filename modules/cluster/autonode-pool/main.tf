#------------------------------------------------------------------------------
# AutoNode Pool Module - Karpenter NodePool CRDs
#
# Creates Karpenter NodePool custom resources on the cluster. Each pool
# maps to a single NodePool CR with instance type(s), capacity type (spot /
# on-demand), labels, taints, limits, weight, and a nodeClassRef.
#
# Supports simple definitions (just name + instance_type) through complex
# multi-type pools with resource limits, weights, and expiry.
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

  # Resolve instance types: prefer explicit list, fall back to single value.
  effective_instance_types = {
    for name, pool in local.pool_map : name => (
      length(pool.instance_types) > 0 ? pool.instance_types : [pool.instance_type]
    )
  }

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
    spec = merge(
      {
        disruption = {
          consolidationPolicy = each.value.consolidation_policy
        }
        template = {
          metadata = length(local.safe_template_labels[each.key]) > 0 ? {
            labels = local.safe_template_labels[each.key]
          } : {}
          spec = merge(
            {
              requirements = concat(
                [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = local.effective_instance_types[each.key]
                }],
                [{
                  key      = "karpenter.sh/capacity-type"
                  operator = "In"
                  values   = [each.value.capacity_type]
                }]
              )
              nodeClassRef = {
                group = var.node_class_group
                kind  = var.node_class_kind
                name  = each.value.node_class
              }
              expireAfter = each.value.expire_after
            },
            length(each.value.taints) > 0 ? {
              taints = [
                for t in each.value.taints : merge(
                  { key = t.key, effect = t.schedule_type },
                  t.value != "" ? { value = t.value } : {}
                )
              ]
            } : {}
          )
        }
      },
      length(each.value.limits) > 0 ? { limits = each.value.limits } : {},
      each.value.weight > 0 ? { weight = each.value.weight } : {}
    )
  })

  server_side_apply = true
  force_conflicts   = true
}
