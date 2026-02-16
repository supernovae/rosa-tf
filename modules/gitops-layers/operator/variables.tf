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

variable "terraform_sa_name" {
  type        = string
  description = <<-EOT
    Name of the Kubernetes ServiceAccount created for Terraform.
    This SA is used for all subsequent Terraform runs after bootstrap.
    The token is stored in Terraform state (must be encrypted at rest).
    
    To rotate the token:
      terraform apply -replace="module.gitops[0].kubernetes_secret_v1.terraform_operator_token"
  EOT
  default     = "terraform-operator"
}

variable "terraform_sa_namespace" {
  type        = string
  description = <<-EOT
    Namespace for the Terraform operator ServiceAccount, Secret, and token.
    
    Uses a dedicated namespace (not kube-system) to avoid ROSA's managed
    admission webhooks that block deletion of resources in system namespaces.
    This allows full Terraform lifecycle management: create, rotate, destroy.
    
    Audit identity: system:serviceaccount:<namespace>:<sa-name>
  EOT
  default     = "rosa-terraform"
}

variable "skip_k8s_destroy" {
  type        = bool
  description = <<-EOT
    When true, removes all Kubernetes resources from Terraform state without
    attempting to delete them from the cluster. Use before destroying a cluster:
      1. terraform apply -var="skip_k8s_destroy=true"
      2. terraform destroy
    
    This prevents Terraform from failing when trying to reach a cluster API
    that no longer exists during destroy.
  EOT
  default     = false
}

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
    ArgoCD will sync from this repo using a single Application resource.
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

variable "enable_layer_certmanager" {
  type        = bool
  description = <<-EOT
    Enable the Cert-Manager layer for automated certificate lifecycle management.
    
    Installs and configures:
    - OpenShift cert-manager operator
    - Let's Encrypt ClusterIssuer with DNS01/Route53 solver
    - Optional Certificate resources for provided domains
    - Optional OpenShift Routes integration for automatic TLS
    
    IMPORTANT: Requires outbound internet access for DNS01 challenge.
    Cannot be used on zero-egress clusters. Use cert_mode=provided instead.
    
    Requires certmanager_role_arn and certmanager_hosted_zone_id from the
    certmanager-resources module.
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
    
    IMPORTANT: 1x.small requires significant cluster resources (6+ m6i.xlarge nodes).
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

#------------------------------------------------------------------------------
# Cert-Manager Layer Configuration (when enabled)
#------------------------------------------------------------------------------

variable "certmanager_role_arn" {
  type        = string
  description = "IAM role ARN for cert-manager Route53 access. Required if enable_layer_certmanager is true."
  default     = ""
}

variable "certmanager_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for DNS01 challenges. Required if enable_layer_certmanager is true."
  default     = ""
}

variable "certmanager_hosted_zone_domain" {
  type        = string
  description = "Domain of the Route53 hosted zone for cert-manager."
  default     = ""
}

variable "certmanager_acme_email" {
  type        = string
  description = <<-EOT
    Email address for Let's Encrypt ACME registration.
    Let's Encrypt sends certificate expiry notifications to this address.
    Required if enable_layer_certmanager is true.
  EOT
  default     = ""
}

variable "certmanager_use_staging_issuer" {
  type        = bool
  description = <<-EOT
    Use Let's Encrypt staging issuer for certificates instead of production.
    
    Staging certificates are NOT trusted by browsers but have much higher
    rate limits (30,000 certs per week vs 50 per week). Use this for
    dev/test environments to avoid hitting production rate limits.
    
    Default: false (production Let's Encrypt)
  EOT
  default     = false
}

variable "certmanager_certificate_domains" {
  type = list(object({
    name        = string
    namespace   = string
    secret_name = string
    domains     = list(string)
  }))
  description = <<-EOT
    List of Certificate resources to create.
    Each entry creates a cert-manager Certificate CR that requests a TLS
    certificate from Let's Encrypt for the specified domains.
    
    Example:
      certmanager_certificate_domains = [
        {
          name        = "apps-wildcard"
          namespace   = "openshift-ingress"
          secret_name = "custom-apps-default-cert"
          domains     = ["*.apps.example.com"]
        }
      ]
    
    Set to [] to only set up the ClusterIssuer without pre-creating certificates.
  EOT
  default     = []
}

variable "certmanager_enable_routes_integration" {
  type        = bool
  description = <<-EOT
    Enable the cert-manager OpenShift Routes integration.
    
    When enabled, you can annotate OpenShift Routes to automatically
    provision TLS certificates:
    
      oc annotate route <name> \
        cert-manager.io/issuer-kind=ClusterIssuer \
        cert-manager.io/issuer-name=letsencrypt-production
    
    Default: true (enabled when cert-manager layer is active)
  EOT
  default     = true
}

variable "certmanager_routes_image" {
  type        = string
  description = <<-EOT
    Container image for the cert-manager OpenShift Routes integration controller.
    
    Override this for GovCloud or air-gapped environments to point to an
    approved registry mirror. Pin to a specific tag for reproducibility.
  EOT
  default     = "ghcr.io/cert-manager/cert-manager-openshift-routes:v0.6.1"
}

#------------------------------------------------------------------------------
# Cert-Manager Custom Ingress Configuration
#------------------------------------------------------------------------------

variable "certmanager_ingress_enabled" {
  type        = bool
  description = "Create a custom IngressController for the cert-manager domain."
  default     = true
}

variable "certmanager_ingress_domain" {
  type        = string
  description = "Domain the custom IngressController serves. Passed from the certmanager module's effective_ingress_domain."
  default     = ""
}

variable "certmanager_ingress_visibility" {
  type        = string
  description = "Visibility of the custom ingress NLB: 'private' or 'public'."
  default     = "private"
}

variable "certmanager_ingress_replicas" {
  type        = number
  description = "Number of router replicas for the custom IngressController."
  default     = 2
}

variable "certmanager_ingress_route_selector" {
  type        = map(string)
  description = "Additional route label selector for the custom IngressController."
  default     = {}
}

variable "certmanager_ingress_namespace_selector" {
  type        = map(string)
  description = "Namespace label selector for the custom IngressController."
  default     = {}
}

variable "certmanager_ingress_cert_secret_name" {
  type        = string
  description = <<-EOT
    Name of the TLS secret for the custom IngressController's default certificate.
    This MUST match the secret_name in your certmanager_certificate_domains entry.
    Automatically derived from the first certificate domain when wired through
    environment main.tf.
  EOT
  default     = "custom-apps-default-cert"
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

