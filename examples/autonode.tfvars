#------------------------------------------------------------------------------
# AutoNode (Karpenter) Example Configuration
#
# !! TECHNOLOGY PREVIEW -- NOT FOR PRODUCTION USE !!
#
# AutoNode on ROSA HCP is a Technology Preview feature. It is not fully
# supported under Red Hat subscription service level agreements, may not
# be functionally complete, and is not intended for production use. Red Hat
# does not guarantee stability or a migration path to GA. Clusters with
# AutoNode enabled should be treated as disposable test environments.
# See: https://access.redhat.com/support/offerings/techpreview
#
# Enables Karpenter-based node autoscaling on ROSA HCP clusters.
# AutoNode replaces traditional machine pool autoscaling with Karpenter's
# bin-packing scheduler for faster, more efficient scaling.
#
# Usage:
#   # Phase 1: Create cluster + IAM
#   terraform apply -var-file=cluster-dev.tfvars
#
#   # Enable AutoNode (manual step between phases)
#   terraform output -raw rosa_enable_autonode_command | bash
#   # Wait ~5 min for Karpenter CRDs: oc get crd | grep karpenter
#
#   # Phase 2: Deploy NodePools + GitOps layers
#   terraform apply -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars
#
# Where gitops-dev.tfvars includes install_gitops = true and the pools below.
#
# Requirements:
#   - OpenShift 4.19+
#   - us-east-1 region (private preview)
#   - Cluster on AutoNode shard (set cluster_properties)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Enable AutoNode
#------------------------------------------------------------------------------

enable_autonode = true

# For private preview, target the AutoNode shard
# cluster_properties = {
#   "provision_shard_id" = "YOUR-SHARD-ID"
# }

#------------------------------------------------------------------------------
# AutoNode Pool Examples
#
# Pools range from simple (just name + instance type) to complex (multi-type
# with limits, weights, taints, and expiry).
#
# Key fields:
#   instance_type  - single type (use this OR instance_types)
#   instance_types - list of types; Karpenter picks best fit
#   capacity_type  - "spot" (default) or "on-demand"
#   labels         - kubernetes.io domain auto-filtered for Karpenter
#   taints         - [{key, value (optional), schedule_type}]
#   limits         - max resources the pool can provision
#   weight         - priority; higher = preferred (default 0)
#   expire_after   - node TTL before replacement (default "720h")
#   consolidation_policy - "WhenEmptyOrUnderutilized" (default) or "WhenEmpty"
#   consolidate_after    - delay before consolidation (default "30s")
#------------------------------------------------------------------------------

autonode_pools = [

  #----------------------------------------------------------------------------
  # Example 1: Simple general-purpose pool (minimal config)
  #
  # Only name and instance_type are required. Everything else defaults:
  # spot pricing, WhenEmptyOrUnderutilized consolidation, 30s consolidate
  # delay, 720h (30 day) node expiry.
  #----------------------------------------------------------------------------
  {
    name          = "general"
    instance_type = "m6a.2xlarge"
  },

  #----------------------------------------------------------------------------
  # Example 2: Multi-type Spot pool with resource limits
  #
  # Karpenter picks the best-fit instance from the list based on pending
  # pod requirements and Spot availability. Limits cap total provisioned
  # resources for cost control.
  #----------------------------------------------------------------------------
  # {
  #   name           = "compute-spot"
  #   instance_types = ["m6a.2xlarge", "m6a.4xlarge", "m7a.2xlarge", "m6i.2xlarge"]
  #   capacity_type  = "spot"
  #   limits         = { cpu = "64", memory = "256Gi" }
  #   expire_after   = "168h"   # Replace nodes after 7 days
  # },

  #----------------------------------------------------------------------------
  # Example 3: GPU pool with taints and labels
  #
  # Taints ensure only GPU-tolerant workloads land here. Weight gives
  # this pool lower priority so general workloads use cheaper nodes first.
  # consolidate_after of 10m avoids thrashing on bursty GPU jobs.
  #----------------------------------------------------------------------------
  # {
  #   name          = "gpu-l40"
  #   instance_type = "g6e.2xlarge"
  #   capacity_type = "spot"
  #   labels = {
  #     "node-role.autonode/gpu" = ""
  #   }
  #   taints = [{
  #     key           = "nvidia.com/gpu"
  #     value         = "true"
  #     schedule_type = "NoSchedule"
  #   }]
  #   weight            = 10
  #   consolidate_after = "10m"
  # },

  #----------------------------------------------------------------------------
  # Example 4: On-demand fallback with WhenEmpty consolidation
  #
  # Paired with a Spot pool of the same instance types, this catches
  # workloads when Spot capacity is unavailable. WhenEmpty consolidation
  # only removes nodes with zero non-daemonset pods.
  #----------------------------------------------------------------------------
  # {
  #   name                 = "fallback-ondemand"
  #   instance_types       = ["m6a.2xlarge", "m6a.4xlarge"]
  #   capacity_type        = "on-demand"
  #   weight               = 1
  #   consolidation_policy = "WhenEmpty"
  #   consolidate_after    = "5m"
  # },
]

#------------------------------------------------------------------------------
# Empty machine pools when using AutoNode for all supplementary compute
#------------------------------------------------------------------------------

# machine_pools = []
