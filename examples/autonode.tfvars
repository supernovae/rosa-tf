# Commercial HCP overlay. Verify OpenShift 4.22+ and service eligibility first.
# Include this during Phase 1 for native activation; keep it in Phase 2 when
# enabling install_gitops. Wait for CRDs and the default node class to be Ready.
# AutoNode cannot be disabled after enablement in RHCS 1.7.8.
enable_autonode = true

autonode_pools = [{
  name                 = "general"
  instance_types       = ["m6i.xlarge", "m7i.xlarge"]
  capacity_type        = "on-demand"
  labels               = { "workload.example.com/tier" = "general" }
  limits               = { cpu = "32", memory = "128Gi" }
  consolidation_policy = "WhenEmpty"
  consolidate_after    = "5m"
  expire_after         = "Never"
}]
# Spot is a separate, explicit workload decision; add appropriate taints and
# tolerations plus disruption/recovery tests before selecting capacity_type=spot.
