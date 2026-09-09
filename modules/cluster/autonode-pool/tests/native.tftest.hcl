mock_provider "kubectl" {}
run "on_demand_native_node_class" {
  command = plan
  variables { autonode_pools = [{ name = "general", instance_type = "m6i.xlarge", labels = { "workload.example.com/tier" = "general" } }] }
  assert {
    condition     = strcontains(kubectl_manifest.nodepool["general"].yaml_body, "on-demand") && strcontains(kubectl_manifest.nodepool["general"].yaml_body, "EC2NodeClass") && strcontains(kubectl_manifest.nodepool["general"].yaml_body, "workload.example.com/tier")
    error_message = "Use on-demand defaults, the managed native node class and unchanged user labels."
  }
}
run "reject_ambiguous_instance_selection" {
  command = plan
  variables { autonode_pools = [{ name = "bad", instance_type = "m6i.xlarge", instance_types = ["m7i.xlarge"] }] }
  expect_failures = [var.autonode_pools]
}
run "reject_silently_dropped_label" {
  command = plan
  variables { autonode_pools = [{ name = "bad", instance_type = "m6i.xlarge", labels = { "node-role.kubernetes.io/worker" = "" } }] }
  expect_failures = [var.autonode_pools]
}
