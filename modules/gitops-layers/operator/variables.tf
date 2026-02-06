#------------------------------------------------------------------------------
# GitOps Module Variables
#
# GITOPS-VAR-CHAIN: This is the operator module's variable interface.
# When adding a variable here, also update:
#   1. environments/*/variables.tf  (all 4 environments)
#   2. environments/*/main.tf       (passthrough in module "gitops" blocks)
#   3. Templates in gitops-layers/layers/ (if used in YAML)
# Search "GITOPS-VAR-CHAIN" to find all touchpoints.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster."
}

variable "cluster_api_url" {
  type        = string
  description = "API URL of the ROSA cluster."
}

variable "cluster_token" {
  type        = string
  description = <<-EOT
    OAuth bearer token for cluster authentication.
    Obtained from the cluster-auth module.
  EOT
  sensitive   = true
}

variable "aws_region" {
  type        = string
  description = "AWS region where the cluster is deployed."
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID."
}

variable "cluster_type" {
  type        = string
  description = <<-EOT
    Type of ROSA cluster: "classic" or "hcp".
    
    This affects monitoring configuration:
    - Classic: SRE manages openshift-monitoring namespace, so we skip
      PrometheusRules there and use user-workload-monitoring instead
    - HCP: Full control over openshift-monitoring namespace
  EOT
  default     = "hcp"

  validation {
    condition     = contains(["classic", "hcp"], var.cluster_type)
    error_message = "Cluster type must be 'classic' or 'hcp'."
  }
}

#------------------------------------------------------------------------------
# Layer Repository Configuration
#------------------------------------------------------------------------------

variable "gitops_repo_url" {
  type        = string
  description = <<-EOT
    Git repository URL for ADDITIONAL static resources to deploy via ArgoCD.
    
    NOTE: This is NOT for the core layers (monitoring, OADP, etc.) - those are
    always managed by Terraform because they require environment-specific values
    (S3 buckets, IAM roles) that Terraform creates.
    
    Use this for your own static Kubernetes resources such as:
    - Projects / Namespaces
    - ResourceQuotas / LimitRanges  
    - NetworkPolicies
    - RBAC (Roles, RoleBindings)
    - Application deployments
    - Any other manifests you want ArgoCD to manage
    
    The repository should contain kustomize-compatible YAML manifests.
    ArgoCD will sync from this repo using the ApplicationSet pattern.
  EOT
  default     = "https://github.com/redhat-openshift-ecosystem/rosa-gitops-layers.git"
}

variable "gitops_repo_revision" {
  type        = string
  description = "Git revision (branch, tag, or commit) for the layers repository."
  default     = "main"
}

variable "gitops_repo_path" {
  type        = string
  description = "Path within the repository to the layers directory."
  default     = "layers"
}

#------------------------------------------------------------------------------
# Layer Enablement Flags
#------------------------------------------------------------------------------

variable "enable_layer_terminal" {
  type        = bool
  description = <<-EOT
    Enable the Web Terminal layer.
    Installs the OpenShift Web Terminal operator for in-console terminal access.
    This layer has no Terraform dependencies.
  EOT
  default     = true
}

variable "enable_layer_oadp" {
  type        = bool
  description = <<-EOT
    Enable the OADP (OpenShift API for Data Protection) layer.
    Requires oadp_bucket_name and oadp_role_arn from the oadp-resources module.
    Provides cluster backup and restore capabilities using Velero.
  EOT
  default     = false
}

variable "enable_layer_virtualization" {
  type        = bool
  description = <<-EOT
    Enable the OpenShift Virtualization layer.
    Requires bare metal nodes via machine_pools variable in tfvars.
    Provides VM capabilities on OpenShift using KubeVirt.
  EOT
  default     = false
}

variable "enable_layer_monitoring" {
  type        = bool
  description = <<-EOT
    Enable the Monitoring and Logging layer.
    Installs and configures:
    - Prometheus with persistent storage and custom retention
    - Loki Operator with S3 backend for log storage
    - Cluster Logging Operator with Vector collectors
    - ClusterLogForwarder for log aggregation
    - PrometheusRules for monitoring stack health alerts
    
    Requires monitoring_bucket_name and monitoring_role_arn from the
    monitoring-resources module.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# OADP Layer Configuration (when enabled)
#------------------------------------------------------------------------------

variable "oadp_bucket_name" {
  type        = string
  description = "S3 bucket name for OADP backups. Required if enable_layer_oadp is true."
  default     = ""
}

variable "oadp_role_arn" {
  type        = string
  description = "IAM role ARN for OADP. Required if enable_layer_oadp is true."
  default     = ""
}

variable "oadp_backup_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain nightly backups.

    A nightly backup schedule is created automatically when OADP is enabled.
    This backs up all user namespaces (excluding OpenShift system namespaces)
    every night at 2:00 AM UTC.

    Set to 0 to disable the automatic backup schedule.
  EOT
  default     = 7
}

#------------------------------------------------------------------------------
# Virtualization Layer Configuration (when enabled)
#------------------------------------------------------------------------------

variable "virt_node_selector" {
  type        = map(string)
  description = <<-EOT
    Node selector for OpenShift Virtualization components.
    Use to place virt-controller, virt-api, and VMs on dedicated nodes.
    Example: { "node-role.kubernetes.io/virtualization" = "" }
    Default: Standard virtualization node label
  EOT
  default = {
    "node-role.kubernetes.io/virtualization" = ""
  }
}

variable "virt_tolerations" {
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string, "")
    effect   = string
  }))
  description = <<-EOT
    Tolerations for OpenShift Virtualization components.
    Use to allow virt components and VMs to run on tainted bare metal nodes.
    Example: [{ key = "virtualization", value = "true", effect = "NoSchedule" }]
    Default: Tolerates standard virtualization taint
  EOT
  default = [
    {
      key      = "virtualization"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  ]
}

#------------------------------------------------------------------------------
# Monitoring Layer Configuration (when enabled)
#------------------------------------------------------------------------------

variable "monitoring_bucket_name" {
  type        = string
  description = "S3 bucket name for Loki log storage. Required if enable_layer_monitoring is true."
  default     = ""
}

variable "monitoring_role_arn" {
  type        = string
  description = "IAM role ARN for Loki S3 access. Required if enable_layer_monitoring is true."
  default     = ""
}

variable "monitoring_loki_size" {
  type        = string
  description = <<-EOT
    LokiStack deployment size. Controls resource allocation for all Loki components.
    
    Available sizes:
    - 1x.extra-small: Development/testing (~2 vCPU, 4GB per component)
    - 1x.small: Small production (~4 vCPU, 8GB per component)
    - 1x.medium: Medium production (~8 vCPU, 16GB per component)
    
    IMPORTANT: 1x.small requires significant cluster resources (6+ m5.xlarge nodes).
    For dev environments, use 1x.extra-small.
  EOT
  default     = "1x.extra-small"

  validation {
    condition     = contains(["1x.demo", "1x.extra-small", "1x.small", "1x.medium"], var.monitoring_loki_size)
    error_message = "LokiStack size must be one of: 1x.demo, 1x.extra-small, 1x.small, 1x.medium"
  }
}

variable "monitoring_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain logs and metrics.
    
    This controls:
    - Prometheus metric retention (converted to hours)
    - Loki log retention (days)
    - S3 lifecycle rules
    
    Recommended:
    - Development: 7 days
    - Production: 30 days
  EOT
  default     = 30
}

variable "monitoring_storage_class" {
  type        = string
  description = <<-EOT
    StorageClass for Prometheus and Loki PVCs.
    Default: gp3-csi (recommended for ROSA)
    
    Note: Both HCP and Classic ROSA clusters use gp3-csi by default.
  EOT
  default     = "gp3-csi"
}

variable "monitoring_prometheus_storage_size" {
  type        = string
  description = <<-EOT
    Size of Prometheus persistent volume.
    Recommended sizing based on retention:
    - 7 days: 50Gi
    - 30 days: 100Gi
    - 90 days: 200Gi
  EOT
  default     = "100Gi"
}

variable "monitoring_node_selector" {
  type        = map(string)
  description = <<-EOT
    Node selector for LokiStack components.
    Use to place Loki on dedicated monitoring nodes.
    Example: { "node-role.kubernetes.io/monitoring" = "" }
    Default: {} (no node selector, uses default scheduling)
  EOT
  default     = {}
}

variable "monitoring_tolerations" {
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string, "")
    effect   = string
  }))
  description = <<-EOT
    Tolerations for LokiStack components.
    Use to allow Loki to run on tainted monitoring nodes.
    Example: [{ key = "workload", value = "monitoring", effect = "NoSchedule" }]
    Default: [] (no tolerations, uses default scheduling)
  EOT
  default     = []
}

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for operator channel selection.
    
    This controls version-specific operator channels:
    
    | Operator        | OCP 4.16-4.18 | OCP 4.19+ |
    |-----------------|---------------|-----------|
    | Loki            | stable-6.2    | stable-6.4|
    | Cluster Logging | stable-6.2    | stable-6.4|
    | OADP            | stable        | stable    |
    | Virtualization  | stable        | stable    |
    | Web Terminal    | fast          | fast      |
    
    Operators using generic channels (stable/fast) auto-select versions.
    Only operators with version-specific channels need this calculation.
    
    Format: "4.XX" (e.g., "4.16", "4.20")
  EOT
  default     = "4.20"
}

#------------------------------------------------------------------------------
# Installation Method
#------------------------------------------------------------------------------

variable "layers_install_method" {
  type        = string
  description = <<-EOT
    How to install resources:
    
    "direct" (default, recommended):
      - Core layers (monitoring, OADP, etc.) are applied by Terraform
      - Works in air-gapped environments
      - No external Git access required from cluster
      - Environment-specific values (S3 buckets, IAM roles) are injected
    
    "applicationset":
      - Creates an ArgoCD ApplicationSet pointing to gitops_repo_url
      - Use for ADDITIONAL static resources (projects, quotas, RBAC, apps)
      - Requires cluster egress to Git
      - Core layers are still applied by Terraform (direct method)
    
    Architecture:
      Terraform (direct)  → Operators, S3 buckets, IAM roles, LokiStack, DPA
      ArgoCD (appset)     → Your static resources from gitops_repo_url
    
    To skip layers entirely, set all enable_layer_* = false.
  EOT
  default     = "direct"

  validation {
    condition     = contains(["direct", "applicationset"], var.layers_install_method)
    error_message = "layers_install_method must be one of: direct, applicationset"
  }
}

#------------------------------------------------------------------------------
# Advanced Configuration
#------------------------------------------------------------------------------

variable "additional_config_data" {
  type        = map(string)
  description = <<-EOT
    Additional key-value pairs to add to the rosa-gitops-config ConfigMap.
    Use this to pass custom configuration to your GitOps layers.
  EOT
  default     = {}
}
