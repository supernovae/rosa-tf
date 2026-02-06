#------------------------------------------------------------------------------
# ROSA Classic Machine Pools Outputs
#------------------------------------------------------------------------------

output "machine_pools" {
  description = "Map of created machine pools with their configurations."
  value = {
    for name, pool in rhcs_machine_pool.pool : name => {
      id                = pool.id
      name              = pool.name
      instance_type     = pool.machine_type
      replicas          = pool.replicas
      autoscaling       = pool.autoscaling_enabled ? { min = pool.min_replicas, max = pool.max_replicas } : null
      spot_enabled      = pool.use_spot_instances
      disk_size         = pool.disk_size
      labels            = pool.labels
      multi_az          = pool.multi_availability_zone
      availability_zone = pool.availability_zone
    }
  }
}

output "pool_names" {
  description = "List of created machine pool names."
  value       = [for pool in rhcs_machine_pool.pool : pool.name]
}

output "pool_count" {
  description = "Number of additional machine pools created."
  value       = length(rhcs_machine_pool.pool)
}
