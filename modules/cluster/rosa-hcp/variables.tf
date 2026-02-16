#------------------------------------------------------------------------------
# ROSA HCP Cluster Module Variables
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA HCP cluster."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,13}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be 1-15 lowercase alphanumeric characters, may include hyphens, and must start with a letter."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for the cluster."
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID where the cluster will be deployed."
}

variable "creator_arn" {
  type        = string
  description = <<-EOT
    ARN of the IAM user or role creating the cluster.
    Required for ROSA HCP. Use data.aws_caller_identity.current.arn.
  EOT
}

variable "private_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    List of private subnet IDs for the cluster.
    Required for all ROSA HCP clusters.
  EOT

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet is required for ROSA HCP."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    List of public subnet IDs for the cluster.
    Required for public ROSA HCP clusters (minimum 2 subnets across 2 AZs).
    Leave empty for private clusters.
  EOT
  default     = []
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones for the cluster."

  validation {
    condition     = length(var.availability_zones) >= 1 && length(var.availability_zones) <= 3
    error_message = "Must specify 1-3 availability zones."
  }
}

#------------------------------------------------------------------------------
# IAM Configuration
#------------------------------------------------------------------------------

variable "oidc_config_id" {
  type        = string
  description = "OIDC configuration ID from the IAM module."
}

variable "installer_role_arn" {
  type        = string
  description = "ARN of the installer IAM role."
}

variable "support_role_arn" {
  type        = string
  description = "ARN of the support IAM role."
}

variable "worker_role_arn" {
  type        = string
  description = "ARN of the worker IAM role."
}

variable "operator_role_prefix" {
  type        = string
  description = "Prefix for operator IAM roles."
}

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for the cluster.
    For HCP, use the version without the 'openshift-v' prefix (e.g., "4.16.0").
  EOT

  validation {
    condition     = can(regex("^4\\.[0-9]+\\.[0-9]+$", var.openshift_version))
    error_message = "OpenShift version must be in format X.Y.Z (e.g., 4.16.0)."
  }
}

variable "channel_group" {
  type        = string
  description = "Channel group for updates: stable, fast, candidate, or eus."
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

variable "skip_version_drift_check" {
  type        = bool
  description = <<-EOT
    Skip the version drift check between control plane and machine pools.
    ROSA HCP requires machine pools to be within n-2 of control plane version.
    Set to true to suppress the warning during upgrades.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Compute Configuration
#------------------------------------------------------------------------------

variable "compute_machine_type" {
  type        = string
  description = "EC2 instance type for default machine pool."
  default     = "m6i.xlarge"
}

variable "replicas" {
  type        = number
  description = "Number of worker nodes in the default machine pool."
  default     = 2

  validation {
    condition     = var.replicas >= 2
    error_message = "HCP requires at least 2 worker nodes."
  }
}

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

variable "machine_cidr" {
  type        = string
  description = "CIDR block for cluster nodes (typically VPC CIDR)."
  default     = "10.0.0.0/16"
}

variable "service_cidr" {
  type        = string
  description = "CIDR block for Kubernetes services."
  default     = "172.30.0.0/16"
}

variable "pod_cidr" {
  type        = string
  description = "CIDR block for pods."
  default     = "10.128.0.0/14"
}

variable "host_prefix" {
  type        = number
  description = "Subnet prefix length for pod networks on each node."
  default     = 23
}

variable "private_cluster" {
  type        = bool
  description = <<-EOT
    Deploy as a private cluster (no public API/ingress endpoints).
    - true: API and ingress only accessible from within VPC
    - false: Public API and ingress endpoints (requires public subnets)
    
    GovCloud: Must be true (private only, enforced)
    Commercial: Can be true or false (default true for security)
    
    Note: HCP control plane connectivity ALWAYS uses AWS PrivateLink
    (workers connect to Red Hat-managed control plane via PrivateLink).
    This setting only controls API/ingress endpoint visibility.
  EOT
  default     = true
}

variable "zero_egress" {
  type        = bool
  description = <<-EOT
    Enable zero-egress mode for fully air-gapped operation.
    
    When enabled:
    - Cluster pulls OpenShift images from Red Hat's regional ECR (not internet)
    - No NAT gateway or internet gateway required
    - VPC endpoints for ECR, S3, STS are required
    - Custom operators must be mirrored to your own ECR
    
    Requirements:
    - private_cluster must be true
    - VPC must have ECR VPC endpoints configured
    
    See: docs/ZERO-EGRESS.md for operator mirroring workflow.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Encryption Configuration
#------------------------------------------------------------------------------

variable "etcd_encryption" {
  type        = bool
  description = "Enable etcd encryption at rest."
  default     = true
}

variable "etcd_kms_key_arn" {
  type        = string
  description = "KMS key ARN for etcd encryption. Required if etcd_encryption is true."
  default     = ""
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "KMS key ARN for EBS volume encryption."
  default     = ""
}

# Note: Proxy configuration is not supported for ROSA HCP clusters via Terraform.
# If proxy is required, configure it post-installation via cluster settings.

#------------------------------------------------------------------------------
# Admin User Configuration
#------------------------------------------------------------------------------

variable "create_admin_user" {
  type        = bool
  description = "Create an htpasswd admin user for initial cluster access."
  default     = true
}

variable "admin_username" {
  type        = string
  description = "Username for the cluster admin."
  default     = "cluster-admin"
}

#------------------------------------------------------------------------------
# Billing Configuration
#------------------------------------------------------------------------------

variable "aws_billing_account_id" {
  type        = string
  description = <<-EOT
    AWS account ID for billing (if different from deployment account).
    Useful for organizations with centralized billing.
    
    Leave empty to use the deployment account ID (Commercial only).
    GovCloud: This field is ignored and always set to null.
  EOT
  default     = ""
}

variable "is_govcloud" {
  type        = bool
  description = <<-EOT
    Whether this is a GovCloud deployment.
    
    GovCloud has different requirements:
    - aws_billing_account_id must be null (not supported)
    - Clusters are always private
    - etcd encryption is mandatory
    
    Known Issue: GovCloud billing support is pending OCM/ROSA CLI updates.
    This variable ensures Commercial clusters work while GovCloud remains compatible.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Wait Configuration
#------------------------------------------------------------------------------

variable "wait_for_create_complete" {
  type        = bool
  description = "Wait for cluster to be ready before returning."
  default     = true
}

variable "wait_for_std_compute_nodes_complete" {
  type        = bool
  description = "Wait for default compute nodes to be ready."
  default     = true
}

#------------------------------------------------------------------------------
# Additional Configuration
#------------------------------------------------------------------------------

variable "cluster_properties" {
  type        = map(string)
  description = "Additional cluster properties."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to cluster resources."
  default     = {}
}

#------------------------------------------------------------------------------
# External Authentication Configuration (HCP Only)
#
# Enables direct integration with external OIDC identity providers for user
# authentication, replacing the built-in OpenShift OAuth server.
#
# This is different from OIDC config for STS (operator roles):
# - OIDC Config for STS: Allows operators to assume IAM roles
# - External Auth: Allows users to authenticate with corporate SSO
#
# IMPORTANT CONSTRAINTS:
# - Must be enabled at cluster creation time
# - Cannot be added to existing clusters
# - Cannot be disabled once enabled
# - Requires OpenShift 4.15.5+
#
# See docs/OIDC.md for setup instructions.
#------------------------------------------------------------------------------

variable "external_auth_providers_enabled" {
  type        = bool
  description = <<-EOT
    Enable external OIDC identity provider authentication.
    
    When enabled, the built-in OpenShift OAuth server is replaced with
    direct integration to external OIDC providers (e.g., Entra ID, Keycloak).
    
    IMPORTANT:
    - Must be enabled at cluster creation (cannot be added later)
    - Cannot be disabled once enabled
    - When enabled, create_admin_user is typically set to false
    - Requires additional configuration via rosa CLI after cluster creation
    
    Benefits:
    - Use corporate identity tokens directly
    - Unified access control across clusters
    - Streamlined automation with shared credentials
    
    See docs/OIDC.md for external authentication setup guide.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Cluster Autoscaler Configuration
#
# For ROSA HCP, the Cluster Autoscaler is fully managed by Red Hat.
# These settings control cluster-wide autoscaling behavior.
#------------------------------------------------------------------------------

variable "cluster_autoscaler_enabled" {
  type        = bool
  description = <<-EOT
    Enable the cluster autoscaler for automatic cluster sizing.
    
    The cluster autoscaler:
    - Adds nodes when pods can't be scheduled due to insufficient resources
    - Removes underutilized nodes (default 50% utilization threshold)
    - Only affects machine pools that have autoscaling enabled
    
    Both cluster autoscaler AND machine pool autoscaling must be enabled
    for automatic scaling to occur.
  EOT
  default     = false
}

variable "autoscaler_max_nodes_total" {
  type        = number
  description = <<-EOT
    Maximum number of nodes across all autoscaling machine pools.
    
    IMPORTANT: This limit only applies to nodes in autoscaling machine pools.
    Nodes in non-autoscaling pools are NOT counted toward this limit.
    
    Example: With max_nodes_total=50 and one non-autoscaling pool with 10 nodes,
    the cluster could have up to 60 total nodes.
  EOT
  default     = 100
}

variable "autoscaler_max_node_provision_time" {
  type        = string
  description = <<-EOT
    Maximum time the autoscaler waits for a node to become ready.
    Format: duration string (e.g., "15m", "30m", "1h")
    
    If a node doesn't become ready within this time, it's considered failed
    and the autoscaler may try to provision a different node.
  EOT
  default     = "25m"
}

variable "autoscaler_max_pod_grace_period" {
  type        = number
  description = <<-EOT
    Graceful termination time in seconds for pods during scale down.
    
    When scaling down, pods are given this much time to terminate gracefully
    before the node is removed. Set higher for stateful workloads.
  EOT
  default     = 600
}

variable "autoscaler_pod_priority_threshold" {
  type        = number
  description = <<-EOT
    Priority threshold for pod scheduling.
    
    Pods with priority below this value:
    - Won't trigger cluster scale up
    - Won't prevent cluster scale down
    
    Useful for "best-effort" workloads that should only run on spare capacity.
    Default: -10 (most pods have priority 0 by default)
  EOT
  default     = -10
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
# For HCP clusters, only compute (worker) security groups are supported
# because the control plane is managed by Red Hat.
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
