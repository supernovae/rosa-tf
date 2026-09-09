#------------------------------------------------------------------------------
# ROSA HCP Machine Pools Module
#
# Manages additional machine pools for ROSA HCP clusters.
# Uses rhcs_hcp_machine_pool resource.
#
# Key HCP characteristics:
# - Version must be within n-2 of control plane
# - Explicit Spot opt-in via RHCS 1.7.8-prerelease.2 (development only)
# - Single subnet per pool
# - Each pool has its own instance_profile (computed by ROSA)
#
# Keep the default on-demand pool for critical platform services.
# See docs/MACHINE-POOLS.md for configuration examples.
# See: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/hcp_machine_pool
#------------------------------------------------------------------------------

data "aws_partition" "current" {}

#------------------------------------------------------------------------------
# Machine Pools
#
# Creates pools from the generic machine_pools list using for_each.
# Each pool is fully configurable with instance type, scaling, labels, taints.
#------------------------------------------------------------------------------

resource "rhcs_hcp_machine_pool" "pool" {
  for_each = { for pool in var.machine_pools : pool.name => pool }

  cluster = var.cluster_id
  name    = each.value.name

  # Replica configuration
  # When autoscaling is enabled, replicas must be null
  replicas = try(each.value.autoscaling.enabled, false) ? null : each.value.replicas

  aws_node_pool = {
    instance_type                 = each.value.instance_type
    use_spot_instances            = each.value.spot.enabled
    max_spot_price                = each.value.spot.enabled ? each.value.spot.max_price : null
    ec2_metadata_http_tokens      = "required"
    disk_size                     = each.value.disk_size
    node_drain_grace_period       = each.value.node_drain_grace_period
    additional_security_group_ids = length(each.value.additional_security_group_ids) > 0 ? each.value.additional_security_group_ids : null
    tags                          = var.tags
  }

  # Version configuration - must be within n-2 of control plane
  version = var.openshift_version

  # Subnet resolution order: availability_zone (via az_subnet_map) → subnet_id → default
  subnet_id = coalesce(
    try(var.az_subnet_map[each.value.availability_zone], null),
    each.value.subnet_id,
    var.subnet_id
  )

  # Autoscaling configuration
  # Provider requires this block but min/max conflict with replicas.
  # When disabled: set enabled=false only (no min/max).
  # When enabled: set enabled=true with min/max (no replicas).
  autoscaling = try(each.value.autoscaling.enabled, false) ? {
    enabled      = true
    min_replicas = each.value.autoscaling.min
    max_replicas = each.value.autoscaling.max
    } : {
    enabled      = false
    min_replicas = null
    max_replicas = null
  }

  # Reserved scheduling signal; Spot remains opt-in for interruption-tolerant pods.
  labels = merge(each.value.labels, { "rosa-tf.io/capacity-type" = each.value.spot.enabled ? "spot" : "on-demand" })

  # Taints for workload isolation
  taints = length(each.value.taints) == 0 && !each.value.spot.enabled ? null : concat([for t in each.value.taints : {
    key           = t.key
    value         = t.value
    schedule_type = t.schedule_type
  }], each.value.spot.enabled ? [{ key = "rosa-tf.io/spot", value = "true", schedule_type = "NoSchedule" }] : [])

  # Auto-repair configuration
  auto_repair = var.auto_repair

  lifecycle {
    precondition {
      condition     = var.openshift_version != ""
      error_message = "An explicit available OpenShift version is required for HCP machine pools."
    }
    precondition {
      condition     = each.value.spot.max_price == null ? true : each.value.spot.enabled && each.value.spot.max_price > 0
      error_message = "Spot price must be positive and supplied only when Spot is enabled."
    }
    precondition {
      condition     = !endswith(each.value.instance_type, ".metal") || !each.value.spot.enabled
      error_message = "Keep virtualization/bare-metal capacity on demand in this deployment model."
    }
    precondition {
      condition     = each.value.node_drain_grace_period >= 0 && each.value.node_drain_grace_period <= 10080 && floor(each.value.node_drain_grace_period) == each.value.node_drain_grace_period
      error_message = "Node drain grace period must be whole minutes in 0–10080; it does not extend Spot interruption notice."
    }
    precondition {
      condition     = !try(each.value.autoscaling.enabled, false) || try(each.value.autoscaling.min >= 0 && each.value.autoscaling.max >= each.value.autoscaling.min && each.value.autoscaling.max > 0, false)
      error_message = "Autoscaling needs nonnegative min and positive max >= min."
    }
    precondition {
      condition     = each.value.availability_zone == null ? true : each.value.subnet_id == null && contains(keys(var.az_subnet_map), each.value.availability_zone)
      error_message = "Select either a known availability_zone or subnet_id, never both; unknown AZs must not silently fall back."
    }
  }
}

#------------------------------------------------------------------------------
# ECR Policy Attachment (Per-Pool)
#
# When attach_ecr_policy = true for a pool, attaches AmazonEC2ContainerRegistryReadOnly
# to that pool's instance profile. This allows workers in that pool to pull from ECR.
#
# The instance_profile is computed by ROSA when the machine pool is created.
# We extract the role name from the instance profile to attach the policy.
#------------------------------------------------------------------------------

locals {
  # Build map of pools that need ECR policy attached
  pools_with_ecr = {
    for name, pool in rhcs_hcp_machine_pool.pool : name => pool
    if try(var.machine_pools[index(var.machine_pools[*].name, name)].attach_ecr_policy, false)
  }
}

# Get IAM instance profile details to extract role name
data "aws_iam_instance_profile" "pool" {
  for_each = local.pools_with_ecr
  name     = each.value.aws_node_pool.instance_profile
}

# Attach ECR readonly policy to the pool's instance profile role
resource "aws_iam_role_policy_attachment" "pool_ecr_readonly" {
  for_each = local.pools_with_ecr

  role       = data.aws_iam_instance_profile.pool[each.key].role_name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
