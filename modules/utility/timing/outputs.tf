#------------------------------------------------------------------------------
# Timing Module Outputs
#------------------------------------------------------------------------------

output "start_time" {
  description = "Timestamp when deployment started (RFC3339 format)."
  value       = local.start_time
}

output "end_time" {
  description = "Timestamp when deployment completed (RFC3339 format)."
  value       = local.end_time
}

output "duration_seconds" {
  description = "Total deployment duration in seconds."
  value       = local.duration_seconds
}

output "duration_minutes" {
  description = "Total deployment duration in whole minutes."
  value       = local.duration_minutes
}

output "duration_human" {
  description = "Human-readable duration (e.g., '15m 32s')."
  value       = local.duration_human
}

output "timing_summary" {
  description = "Complete timing summary for the stage."
  value = local.enabled ? {
    stage            = var.stage
    start_time       = local.start_time
    end_time         = local.end_time
    duration_seconds = local.duration_seconds
    duration_human   = local.duration_human
  } : null
}
