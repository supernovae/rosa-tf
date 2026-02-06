#------------------------------------------------------------------------------
# ROSA HCP Machine Pools Module
#
# Manages additional machine pools for ROSA HCP clusters.
# Uses rhcs_hcp_machine_pool resource.
#
# Key HCP characteristics:
# - Version must be within n-2 of control plane
# - No spot instance support (coming soon)
# - Single subnet per pool
# - Each pool has its own instance_profile (computed by ROSA)
#
# ROADMAP: When HCP supports 0-worker default pools (~4.22 timeframe),
# consolidate the default worker pool (compute_machine_type/worker_node_count)
# into the machine_pools list so there is a single pool configuration pattern.
# Currently HCP requires a default pool at cluster creation time.
#
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
    instance_type = each.value.instance_type
  }

  # Version configuration - must be within n-2 of control plane
  version = var.openshift_version

  # Subnet configuration - use pool-specific or default
  subnet_id = coalesce(each.value.subnet_id, var.subnet_id)

  # Autoscaling configuration
  # Provider requires this block but min/max conflict with replicas.
  # When disabled: set enabled=false only (no min/max).
  # When enabled: set enabled=true with min/max (no replicas).
  autoscaling = try(each.value.autoscaling.enabled, false) ? {
    enabled      = true
    min_replicas = each.value.autoscaling.min
    max_replicas = each.value.autoscaling.max
    } : {
    enabled = false
  }

  # Labels for workload targeting
  labels = each.value.labels

  # Taints for workload isolation
  taints = [for t in each.value.taints : {
    key           = t.key
    value         = t.value
    schedule_type = t.schedule_type
  }]

  # Auto-repair configuration
  auto_repair = var.auto_repair

  lifecycle {
    precondition {
      condition     = var.openshift_version != "" || var.skip_version_validation
      error_message = "OpenShift version is required for HCP machine pools. Set skip_version_validation = true to skip."
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
    if try(var.machine_pools[index(var.machine_pools.*.name, name)].attach_ecr_policy, false)
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
