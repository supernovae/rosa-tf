# OADP overlay. Requires a supported, approved 4.19–4.22 cluster base.
# 4.18 is deliberately blocked; do not force a newer OADP onto it.
# Provision AWS resources first with install_gitops=false, then apply layers.
install_gitops             = true
enable_layer_oadp          = true
oadp_backup_retention_days = 30
oadp_config = {
  support_confirmed         = false # Set true only after the support/readiness review.
  install_plan_approval     = "Manual"
  schedule_enabled          = true
  schedule_paused           = true # Unpause only AFTER a successful backup AND restore test.
  included_namespaces       = ["vm-workloads"]
  schedule                  = "0 2 * * *"
  virtualization_enabled    = true # Also auto-enabled when the virtualization layer is enabled.
  filesystem_backup_enabled = false
  node_agent_tolerations = [{
    key = "virtualization", operator = "Equal", value = "true", effect = "NoSchedule"
  }]
}
# Combine with approved virtualization and NetApp overlays as needed.
# Whole object/list values replace previous tfvars values; merge them deliberately.
# This file does not install Virtualization or create the workload namespace.
