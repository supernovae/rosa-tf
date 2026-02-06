#------------------------------------------------------------------------------
# Timing Module
#
# Captures timestamps at different stages of deployment to measure duration.
# Useful for debugging and performance analysis.
#
# Usage:
#   module "timing" {
#     source  = "../../modules/utility/timing"
#     enabled = var.enable_timing
#     stage   = "cluster"
#     depends_on_resources = [module.rosa_cluster]
#   }
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.4.6"
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
  }
}

#------------------------------------------------------------------------------
# Start Time - Captured immediately when module is created
#------------------------------------------------------------------------------

resource "time_static" "start" {
  count = var.enabled ? 1 : 0
}

#------------------------------------------------------------------------------
# End Time - Captured after dependent resources complete
#
# Uses a null_resource to create a dependency chain:
# start -> depends_on_resources -> end
#------------------------------------------------------------------------------

resource "null_resource" "dependency_tracker" {
  count = var.enabled ? 1 : 0

  triggers = {
    # Re-run if any dependency changes
    dependencies = join(",", var.dependency_ids)
  }
}

resource "time_static" "end" {
  count = var.enabled ? 1 : 0

  depends_on = [null_resource.dependency_tracker]
}

#------------------------------------------------------------------------------
# Local Calculations
#------------------------------------------------------------------------------

locals {
  enabled = var.enabled

  start_time = local.enabled ? time_static.start[0].rfc3339 : null
  end_time   = local.enabled ? time_static.end[0].rfc3339 : null

  # Calculate duration in seconds
  start_unix = local.enabled ? time_static.start[0].unix : 0
  end_unix   = local.enabled ? time_static.end[0].unix : 0

  duration_seconds           = local.enabled ? local.end_unix - local.start_unix : 0
  duration_minutes           = local.enabled ? floor(local.duration_seconds / 60) : 0
  duration_remainder_seconds = local.enabled ? local.duration_seconds % 60 : 0

  # Human-readable duration
  duration_human = local.enabled ? format("%dm %ds", local.duration_minutes, local.duration_remainder_seconds) : "timing disabled"
}
