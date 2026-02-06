#------------------------------------------------------------------------------
# ROSA HCP Machine Pools Outputs
#------------------------------------------------------------------------------

output "machine_pools" {
  description = "Map of created machine pools with their configurations."
  value = {
    for name, pool in rhcs_hcp_machine_pool.pool : name => {
      id               = pool.id
      name             = pool.name
      instance_type    = pool.aws_node_pool.instance_type
      instance_profile = pool.aws_node_pool.instance_profile
      replicas         = pool.replicas
      autoscaling      = pool.autoscaling
      labels           = pool.labels
      status           = pool.status
      ecr_enabled      = contains(keys(local.pools_with_ecr), name)
    }
  }
}

output "pool_names" {
  description = "List of created machine pool names."
  value       = [for pool in rhcs_hcp_machine_pool.pool : pool.name]
}

output "pool_count" {
  description = "Number of additional machine pools created."
  value       = length(rhcs_hcp_machine_pool.pool)
}

output "pool_instance_profiles" {
  description = "Map of pool names to their instance profiles (for ECR policy attachment)."
  value = {
    for name, pool in rhcs_hcp_machine_pool.pool : name => pool.aws_node_pool.instance_profile
  }
}
