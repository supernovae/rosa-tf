#------------------------------------------------------------------------------
# ROSA Cluster Module Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version for the cluster."
}

variable "channel_group" {
  type        = string
  description = "Update channel group: 'eus' for Extended Update Support, 'stable' for standard releases."
  default     = "stable"

  validation {
    condition     = contains(["stable", "fast", "candidate", "eus"], var.channel_group)
    error_message = "Channel group must be one of: stable, fast, candidate, eus."
  }
}

variable "upgrade_acknowledgements_for" {
  type        = string
  description = <<-EOT
    Acknowledge upgrade to this version when breaking changes exist.
    Required when upgrading to versions with removed Kubernetes APIs.
    Example: "4.17" to acknowledge upgrade to 4.17.x
    Leave empty for normal operations.
  EOT
  default     = null
}

variable "aws_region" {
  type        = string
  description = "AWS region for the cluster."
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones for the cluster."
}

#------------------------------------------------------------------------------
# VPC Configuration
#------------------------------------------------------------------------------

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of private subnets for the cluster."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    IDs of public subnets for the cluster.
    Required for public clusters (private = false).
    Leave empty for private clusters.
  EOT
  default     = []
}

variable "machine_cidr" {
  type        = string
  description = "CIDR block for the VPC."
}

variable "pod_cidr" {
  type        = string
  description = "CIDR block for pods."
  default     = "10.128.0.0/14"
}

variable "service_cidr" {
  type        = string
  description = "CIDR block for services."
  default     = "172.30.0.0/16"
}

variable "host_prefix" {
  type        = number
  description = "Subnet prefix for each node."
  default     = 23
}

#------------------------------------------------------------------------------
# Worker Configuration
#------------------------------------------------------------------------------

variable "compute_machine_type" {
  type        = string
  description = "EC2 instance type for worker nodes."
  default     = "m6i.xlarge"
}

variable "worker_node_count" {
  type        = number
  description = "Number of worker nodes."
  default     = 3
}

variable "worker_disk_size" {
  type        = number
  description = "Root disk size in GB for worker nodes."
  default     = 300
}

variable "default_mp_labels" {
  type        = map(string)
  description = "Labels for the default machine pool."
  default     = null
}

variable "autoscaling_enabled" {
  type        = bool
  description = "Enable autoscaling for the default machine pool."
  default     = false
}

variable "min_replicas" {
  type        = number
  description = "Minimum number of replicas when autoscaling is enabled."
  default     = null
}

variable "max_replicas" {
  type        = number
  description = "Maximum number of replicas when autoscaling is enabled."
  default     = null
}

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

variable "account_role_prefix" {
  type        = string
  description = "Prefix for account IAM roles."
}

variable "operator_role_prefix" {
  type        = string
  description = "Prefix for operator IAM roles."
}

variable "oidc_config_id" {
  type        = string
  description = "ID of the OIDC configuration."
}

variable "path" {
  type        = string
  description = "IAM path for roles."
  default     = "/"
}

#------------------------------------------------------------------------------
# Cluster Access Configuration
#------------------------------------------------------------------------------

variable "private_cluster" {
  type        = bool
  description = <<-EOT
    Deploy as a private cluster (no public API/ingress endpoints).
    - true: API and ingress only accessible from within VPC
    - false: Public API and ingress endpoints (requires public subnets)
    
    GovCloud: Must be true (private only, enforced)
    Commercial: Can be true or false (default true for security)
    
    Note: Private clusters use AWS PrivateLink for Red Hat SRE access.
    Public clusters allow SRE access via the public API endpoint.
  EOT
  default     = true
}

variable "multi_az" {
  type        = bool
  description = <<-EOT
    Deploy cluster across multiple availability zones.
    - true: Control plane and workers spread across AZs (HA)
    - false: Single AZ deployment (dev/test)
  EOT
  default     = true
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "fips" {
  type        = bool
  description = <<-EOT
    Enable FIPS 140-2 validated cryptographic modules.
    - true: Required for GovCloud/FedRAMP, uses FIPS-validated crypto
    - false: Standard cryptographic modules
    
    GovCloud: Must be true
    Commercial: Optional (set true for regulated workloads)
  EOT
  default     = true
}

variable "etcd_encryption" {
  type        = bool
  description = "Enable etcd encryption."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = <<-EOT
    ARN of the KMS key for cluster encryption (EBS volumes).
    This key encrypts all cluster storage: control plane, workers, PVs.
    
    - If provided: Customer-managed KMS key (recommended)
    - If null: AWS-managed encryption (still encrypted, less control)
  EOT
  default     = null
}

variable "attach_ecr_policy" {
  type        = bool
  description = <<-EOT
    Attach AmazonEC2ContainerRegistryReadOnly policy to worker role.
    Enables worker nodes to pull images from ECR repositories.
    Required when using ECR for container images or zero-egress operator mirroring.
    
    Note: This attaches to the account-level Worker role, affecting all clusters
    that use the same account role prefix.
  EOT
  default     = false
}

variable "disable_workload_monitoring" {
  type        = bool
  description = "Disable user workload monitoring."
  default     = false
}

variable "create_admin_user" {
  type        = bool
  description = "Create htpasswd admin user for initial cluster access."
  default     = true
}

variable "admin_username" {
  type        = string
  description = "Admin username for htpasswd IDP."
  default     = "cluster-admin"
}

#------------------------------------------------------------------------------
# Proxy Configuration
#------------------------------------------------------------------------------

variable "http_proxy" {
  type        = string
  description = "HTTP proxy URL."
  default     = null
}

variable "https_proxy" {
  type        = string
  description = "HTTPS proxy URL."
  default     = null
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated list of domains/IPs to exclude from proxy."
  default     = null
}

variable "additional_trust_bundle" {
  type        = string
  description = "PEM-encoded CA bundle for proxy."
  default     = null
}

#------------------------------------------------------------------------------
# Cluster Autoscaler Configuration
# Controls cluster-wide autoscaling behavior (separate from machine pool autoscaling)
#------------------------------------------------------------------------------

variable "cluster_autoscaler_enabled" {
  type        = bool
  description = <<-EOT
    Enable the cluster autoscaler.
    This configures cluster-wide autoscaling behavior.
    
    Note: This is separate from machine pool autoscaling (autoscaling_enabled).
    - Machine pool autoscaling: controls IF pools can scale
    - Cluster autoscaler: controls HOW scaling works (thresholds, timing, limits)
    
    Both should be enabled for full autoscaling capability.
  EOT
  default     = false
}

variable "autoscaler_max_node_provision_time" {
  type        = string
  description = "Maximum time to provision a new node before considering it failed."
  default     = "15m"
}

variable "autoscaler_balance_similar_node_groups" {
  type        = bool
  description = "Balance similar node groups when scaling."
  default     = true
}

variable "autoscaler_skip_nodes_with_local_storage" {
  type        = bool
  description = "Skip nodes with local storage when scaling down."
  default     = true
}

variable "autoscaler_log_verbosity" {
  type        = number
  description = "Log verbosity level (1-10)."
  default     = 1
}

variable "autoscaler_max_pod_grace_period" {
  type        = number
  description = "Maximum grace period for pod termination during scale down (seconds)."
  default     = 600
}

variable "autoscaler_pod_priority_threshold" {
  type        = number
  description = "Pods with priority below this won't prevent scale down."
  default     = -10
}

variable "autoscaler_ignore_daemonsets_utilization" {
  type        = bool
  description = "Ignore DaemonSet pods when calculating node utilization."
  default     = true
}

variable "autoscaler_max_nodes_total" {
  type        = number
  description = <<-EOT
    Maximum total nodes in the cluster (control plane + all workers).
    Set this to prevent runaway scaling.
    
    Recommended: account for control plane (3 nodes multi-az, 1 single-az) plus
    maximum expected workers. Leave headroom for surge.
  EOT
  default     = 100
}

variable "autoscaler_scale_down_enabled" {
  type        = bool
  description = "Enable scale down of underutilized nodes."
  default     = true
}

variable "autoscaler_scale_down_delay_after_add" {
  type        = string
  description = "Delay after adding a node before considering it for scale down."
  default     = "10m"
}

variable "autoscaler_scale_down_delay_after_delete" {
  type        = string
  description = "Delay after deleting a node before considering more scale downs."
  default     = "0s"
}

variable "autoscaler_scale_down_delay_after_failure" {
  type        = string
  description = "Delay after a failed scale down before retrying."
  default     = "3m"
}

variable "autoscaler_scale_down_unneeded_time" {
  type        = string
  description = "How long a node must be unneeded before it's eligible for scale down."
  default     = "10m"
}

variable "autoscaler_scale_down_utilization_threshold" {
  type        = string
  description = <<-EOT
    Node utilization threshold below which scale down is considered.
    Value between 0 and 1. Default 0.5 means scale down if < 50% utilized.
  EOT
  default     = "0.5"
}

#------------------------------------------------------------------------------
# Additional Security Groups (Optional)
#
# Attach additional security groups to cluster nodes for custom network
# access control beyond ROSA's default security groups.
#
# IMPORTANT: Security groups can only be attached at cluster CREATION time.
# They cannot be added or modified after the cluster is deployed.
#
# Classic clusters support security groups for:
# - Compute (worker) nodes
# - Control plane (master) nodes
# - Infrastructure nodes
#------------------------------------------------------------------------------

variable "aws_additional_compute_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of additional security group IDs to attach to compute/worker nodes.
    
    These security groups are applied IN ADDITION to the default ROSA security groups.
    Use this for:
    - Allowing traffic from on-premises networks
    - Restricting egress to specific destinations
    - Integrating with existing VPC security policies
    
    IMPORTANT: Can only be set at cluster creation time. Cannot be modified later.
    
    Example: ["sg-abc123", "sg-def456"]
  EOT
  default     = []
}

variable "aws_additional_control_plane_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of additional security group IDs to attach to control plane (master) nodes.
    
    Use this to:
    - Allow API server access from specific networks
    - Restrict etcd communication paths
    - Integrate with on-premises security policies
    
    IMPORTANT: Can only be set at cluster creation time. Cannot be modified later.
    
    Example: ["sg-abc123"]
  EOT
  default     = []
}

variable "aws_additional_infra_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of additional security group IDs to attach to infrastructure nodes.
    
    Infrastructure nodes run cluster services like routers and the internal registry.
    Use this to control traffic to/from these services.
    
    IMPORTANT: Can only be set at cluster creation time. Cannot be modified later.
    
    Example: ["sg-abc123"]
  EOT
  default     = []
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
