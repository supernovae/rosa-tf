#------------------------------------------------------------------------------
# ROSA Classic Machine Pools Module
#
# Manages additional machine pools for ROSA Classic clusters.
# Uses rhcs_machine_pool resource.
#
# Key Classic characteristics:
# - Supports spot instances (HCP coming soon)
# - Supports multi-AZ distribution
# - Configurable disk size
#
# See docs/MACHINE-POOLS.md for configuration examples.
# See: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/machine_pool
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Machine Pools
#
# Creates pools from the generic machine_pools list using for_each.
# Each pool is fully configurable with instance type, scaling, spot, labels, taints.
#------------------------------------------------------------------------------

resource "rhcs_machine_pool" "pool" {
  for_each = { for pool in var.machine_pools : pool.name => pool }

  cluster      = var.cluster_id
  name         = each.value.name
  machine_type = each.value.instance_type

  # Autoscaling configuration
  autoscaling_enabled = try(each.value.autoscaling.enabled, false)
  min_replicas        = try(each.value.autoscaling.enabled, false) ? each.value.autoscaling.min : null
  max_replicas        = try(each.value.autoscaling.enabled, false) ? each.value.autoscaling.max : null
  replicas            = try(each.value.autoscaling.enabled, false) ? null : each.value.replicas

  # Spot instance configuration (Classic feature)
  use_spot_instances = try(each.value.spot.enabled, false)
  max_spot_price     = try(each.value.spot.enabled, false) ? each.value.spot.max_price : null

  # Disk configuration
  disk_size = each.value.disk_size

  # Labels for workload targeting
  labels = each.value.labels

  # Taints for workload isolation
  taints = each.value.taints

  # Subnet placement
  subnet_id = each.value.subnet_id

  # AZ configuration
  multi_availability_zone = each.value.multi_az
  availability_zone       = each.value.multi_az ? null : each.value.availability_zone
}
