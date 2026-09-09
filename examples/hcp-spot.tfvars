# HCP-only DEVELOPMENT overlay: requires RHCS 1.7.8-prerelease.2 and regional/API support.
# Keep the base workers and all critical/stateful services on demand.
machine_pools = [{
  name          = "spot-batch"
  instance_type = "m6i.xlarge"
  autoscaling   = { enabled = true, min = 0, max = 3 }
  spot          = { enabled = true }
  # Optional numeric max_price; omit to use the provider on-demand price cap.
  # The module adds rosa-tf.io/capacity-type=spot and a NoSchedule Spot taint.
  labels = { "workload.example.com/type" = "interruptible" }
}]
