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
#   - AutoNode must be enabled through the native RHCS auto_node configuration
#   - Karpenter CRDs must be present (~5 min after enabling AutoNode)
#   - kubectl provider must be configured with cluster auth
#------------------------------------------------------------------------------

locals {
  pool_map = { for pool in var.autonode_pools : pool.name => pool }

  # Resolve the validated, mutually exclusive instance-type selectors.
  effective_instance_types = {
    for name, pool in local.pool_map : name => (
      length(pool.instance_types) > 0 ? pool.instance_types : [pool.instance_type]
    )
  }
}

resource "kubectl_manifest" "nodepool" {
  for_each = local.pool_map

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
          consolidateAfter    = each.value.consolidate_after
        }
        template = {
          metadata = length(each.value.labels) > 0 ? {
            labels = each.value.labels
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
  force_conflicts   = false
}
