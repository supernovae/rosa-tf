mock_provider "rhcs" {}
mock_provider "aws" {}
variables {
  cluster_id        = "test-cluster"
  openshift_version = "4.22.0"
  subnet_id         = "subnet-0123456789abcdef0"
  machine_pools     = [{ name = "batch", instance_type = "m6i.xlarge", spot = { enabled = true, max_price = 0.2 }, autoscaling = { enabled = true, min = 0, max = 3 } }]
}
run "isolated_spot_imdsv2" {
  command = plan
  assert {
    condition     = rhcs_hcp_machine_pool.pool["batch"].aws_node_pool.use_spot_instances && rhcs_hcp_machine_pool.pool["batch"].aws_node_pool.max_spot_price == 0.2 && rhcs_hcp_machine_pool.pool["batch"].aws_node_pool.ec2_metadata_http_tokens == "required"
    error_message = "Use the native Spot schema with a numeric price and IMDSv2."
  }
  assert {
    condition     = rhcs_hcp_machine_pool.pool["batch"].replicas == null && rhcs_hcp_machine_pool.pool["batch"].labels["rosa-tf.io/capacity-type"] == "spot" && anytrue([for t in rhcs_hcp_machine_pool.pool["batch"].taints : t.key == "rosa-tf.io/spot" && t.schedule_type == "NoSchedule"])
    error_message = "Spot must be explicitly targeted/tolerated and autoscaling must not set replicas."
  }
}
run "on_demand_default" {
  command = plan
  variables { machine_pools = [{ name = "system", instance_type = "m6i.xlarge" }] }
  assert {
    condition     = !rhcs_hcp_machine_pool.pool["system"].aws_node_pool.use_spot_instances && rhcs_hcp_machine_pool.pool["system"].aws_node_pool.max_spot_price == null
    error_message = "Ordinary worker pools remain on demand."
  }
}
run "reject_bad_price" {
  command = plan
  variables { machine_pools = [{ name = "batch", instance_type = "m6i.xlarge", spot = { enabled = true, max_price = -1 } }] }
  expect_failures = [rhcs_hcp_machine_pool.pool]
}
run "reject_unknown_az" {
  command = plan
  variables { machine_pools = [{ name = "batch", instance_type = "m6i.xlarge", availability_zone = "unknown" }] }
  expect_failures = [rhcs_hcp_machine_pool.pool]
}
run "reject_bad_scaling" {
  command = plan
  variables { machine_pools = [{ name = "batch", instance_type = "m6i.xlarge", autoscaling = { enabled = true, min = 3, max = 1 } }] }
  expect_failures = [rhcs_hcp_machine_pool.pool]
}
