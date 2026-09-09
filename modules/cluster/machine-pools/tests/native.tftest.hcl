mock_provider "rhcs" {}
variables {
  cluster_id = "test-cluster"
  tags       = { Environment = "test" }
  machine_pools = [{
    name                              = "batch", instance_type = "m6i.xlarge", multi_az = false
    spot                              = { enabled = true, max_price = 0.25 }
    autoscaling                       = { enabled = true, min = 0, max = 3 }
    aws_tags                          = { Workload = "batch" }
    aws_additional_security_group_ids = ["sg-0123456789abcdef0"]
  }]
}
run "native_spot_and_security_groups" {
  command = plan
  assert {
    condition     = rhcs_machine_pool.pool["batch"].max_spot_price == 0.25 && rhcs_machine_pool.pool["batch"].replicas == null && rhcs_machine_pool.pool["batch"].aws_tags["Workload"] == "batch" && length(rhcs_machine_pool.pool["batch"].aws_additional_security_group_ids) == 1 && !rhcs_machine_pool.pool["batch"].ignore_deletion_error
    error_message = "Use numeric Spot prices, mutually exclusive scaling, native tags/SGs and fail-closed deletion."
  }
}
run "empty_taints_omitted" {
  command = plan
  variables { machine_pools = [{ name = "base", instance_type = "m6i.xlarge" }] }
  assert {
    condition     = rhcs_machine_pool.pool["base"].taints == null
    error_message = "Omit empty taints rather than sending an invalid list to RHCS."
  }
}
