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
  description = "Legacy count switch: true plans resource deletion, not state removal, and does not bypass refresh. Keep the API reachable; see docs/GITOPS.md."
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
  description = "Explicit HTTPS workload repository; requires gitops_application.enabled. Only approved namespaced workload kinds are allowed; Terraform owns platform layers."
  default     = ""
}

variable "gitops_repo_revision" {
  type        = string
  description = "Git revision (branch, tag, or commit) for the layers repository."
  default     = "main"
}

variable "gitops_repo_path" {
  type        = string
  description = "Path within the workload repository to a manifest or Kustomize directory."
  default     = "."
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

variable "monitoring_enable_perses" {
  type        = bool
  description = "Enable GA Perses console dashboards. Requires COO >=1.5 in the selected catalog; verify before enabling."
  default     = false
}

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
  description = "LokiStack resource profile. Size using measured ingestion/query load and the selected release sizing guide; a fixed node count does not guarantee capacity."
  default     = "1x.extra-small"

  validation {
    condition     = contains(["1x.demo", "1x.extra-small", "1x.small", "1x.medium"], var.monitoring_loki_size)
    error_message = "LokiStack size must be one of: 1x.demo, 1x.extra-small, 1x.small, 1x.medium"
  }
}

variable "monitoring_retention_days" {
  type        = number
  description = "Retention days for user-workload metrics and Loki compactor; also the noncurrent S3 version expiration period. Physical data lifetime can exceed query retention."
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
  description = "PVC size per user-workload Prometheus replica. Size from active series, sample rate and retention, not retention alone."
  default     = "100Gi"
}

variable "monitoring_loki_ingestion_rate" {
  type        = number
  description = <<-EOT
    Per-tenant Loki ingestion rate limit in MB/s.
    The 1x.extra-small default (~4 MB/s) is too low for clusters running
    multiple operators. Increase if Vector logs show 429 Too Many Requests.
  EOT
  default     = 10
}

variable "monitoring_loki_ingestion_burst_size" {
  type        = number
  description = <<-EOT
    Per-tenant Loki ingestion burst size in MB.
    Should be >= ingestion_rate. Allows short bursts above the sustained rate
    (e.g., operator restarts, deployment rollouts).
  EOT
  default     = 20
}

variable "monitoring_node_selector" {
  type        = map(string)
  description = "Node selector for Loki and user-workload Prometheus, Thanos Ruler and Alertmanager. Does not move ROSA platform monitoring or collectors."
  default     = {}
}

variable "monitoring_tolerations" {
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string, "")
    effect   = string
  }))
  description = "Tolerations for Loki and user-workload metrics components. Collectors must remain eligible on all worker architectures."
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
  description = "Opt in to a separately reviewed community Routes controller (not the Red Hat operator). Prefer Certificate resources and IngressController TLS."
  default     = false
}

variable "certmanager_routes_image" {
  type        = string
  description = "Explicitly approved, digest-pinned community Routes controller image; required only for opt-in legacy integration."
  default     = ""
  validation {
    condition     = !var.certmanager_enable_routes_integration || can(regex("@sha256:[0-9a-f]{64}$", var.certmanager_routes_image))
    error_message = "The optional community Routes controller requires an approved digest-pinned image."
  }
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

#------------------------------------------------------------------------------
# EFS Storage (AWS EFS CSI Driver) Configuration
#------------------------------------------------------------------------------

variable "enable_layer_efs_storage" {
  type        = bool
  description = <<-EOT
    Enable the EFS Storage layer (AWS EFS CSI Driver + StorageClass).
    Installs the EFS CSI Driver Operator, creates credentials secret,
    deploys ClusterCSIDriver, and creates an efs-sc StorageClass.
    Works on Classic/HCP and Commercial/GovCloud.
  EOT
  default     = false
}

variable "efs_file_system_id" {
  type        = string
  description = "EFS file system ID for StorageClass. From the efs-storage resources module."
  default     = ""
}

variable "efs_role_arn" {
  type        = string
  description = "IAM role ARN for EFS CSI driver IRSA. From the efs-storage resources module."
  default     = ""
}

variable "efs_storage_class_name" {
  type        = string
  description = "Name of the EFS StorageClass to create."
  default     = "efs-sc"
}

#------------------------------------------------------------------------------
# NetApp Storage (FSx ONTAP + Trident) Configuration
#------------------------------------------------------------------------------

variable "enable_layer_netapp_storage" {
  type        = bool
  description = <<-EOT
    Enable the NetApp Storage layer (FSx ONTAP + NetApp Trident).
    Installs Trident Operator, configures NAS and SAN backends,
    and creates StorageClasses for NFS (RWX) and iSCSI (block).
  EOT
  default     = false
}

variable "fsx_svm_management_ip" {
  type        = string
  description = "FSx ONTAP SVM management endpoint IP. From the netapp-storage resources module."
  default     = ""
}

variable "fsx_svm_name" {
  type        = string
  description = "FSx ONTAP SVM name. From the netapp-storage resources module."
  default     = ""
}

variable "fsx_admin_password" {
  type        = string
  description = "FSx ONTAP SVM vsadmin password for Trident backend authentication."
  default     = ""
  sensitive   = true
}


variable "netapp_trident_log_level" {
  type        = string
  description = "Trident log verbosity: info, debug, or trace."
  default     = "info"

  validation {
    condition     = contains(["info", "debug", "trace"], var.netapp_trident_log_level)
    error_message = "netapp_trident_log_level must be info, debug, or trace."
  }
}

variable "netapp_trident_image" {
  type        = string
  description = "Custom Trident image for air-gapped or GovCloud deployments. Empty uses default."
  default     = ""
}

#------------------------------------------------------------------------------
# OpenShift AI (RHOAI) Configuration
#------------------------------------------------------------------------------

variable "enable_layer_openshift_ai" {
  type        = bool
  description = "Enable OpenShift AI layer (NFD, NVIDIA GPU Operator, RHOAI)."
  default     = false
}

variable "openshift_ai_install_nfd" {
  type        = bool
  description = "Install Node Feature Discovery operator as part of OpenShift AI. Disable if NFD already installed."
  default     = true
}

variable "openshift_ai_install_gpu_operator" {
  type        = bool
  description = "Install NVIDIA GPU Operator. Disable for CPU-only AI workloads."
  default     = true
}

variable "openshift_ai_install_kueue" {
  type        = bool
  description = "Install the Red Hat build of Kueue Operator for workload management. Required when kueue DSC component is Unmanaged."
  default     = true
}

variable "openshift_ai_kueue_auto_create_queues" {
  type        = bool
  description = "Have RHOAI create default ClusterQueue and LocalQueue resources when the Kueue component is Unmanaged."
  default     = true
}

variable "openshift_ai_kueue_default_cluster_queue_name" {
  type        = string
  description = "Name of the default ClusterQueue created by RHOAI when automatic queue creation is enabled."
  default     = "default"

  validation {
    condition     = length(var.openshift_ai_kueue_default_cluster_queue_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.openshift_ai_kueue_default_cluster_queue_name))
    error_message = "openshift_ai_kueue_default_cluster_queue_name must be a valid DNS subdomain of at most 253 characters."
  }
}

variable "openshift_ai_kueue_default_local_queue_name" {
  type        = string
  description = "Name of the default LocalQueue created by RHOAI when automatic queue creation is enabled."
  default     = "default"

  validation {
    condition     = length(var.openshift_ai_kueue_default_local_queue_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.openshift_ai_kueue_default_local_queue_name))
    error_message = "openshift_ai_kueue_default_local_queue_name must be a valid DNS subdomain of at most 253 characters."
  }
}

variable "openshift_ai_kserve_raw_deployment_service_config" {
  type        = string
  description = "KServe service type for RawDeployment inference services: Headless or Headed."
  default     = "Headless"

  validation {
    condition     = contains(["Headless", "Headed"], var.openshift_ai_kserve_raw_deployment_service_config)
    error_message = "openshift_ai_kserve_raw_deployment_service_config must be Headless or Headed."
  }
}

variable "openshift_ai_create_s3" {
  type        = bool
  description = "Create S3 bucket for RHOAI pipeline artifacts. Only required when aipipelines component is Managed. Model serving uses OCI/PVC in RHOAI v3+."
  default     = false
}

variable "openshift_ai_enable_fips" {
  type        = bool
  description = "Enable FIPS mode for GPU operator."
  default     = false
}

variable "openshift_ai_components" {
  type        = map(string)
  description = <<-EOT
    DataScienceCluster component and subcomponent states (RHOAI 3.5, DSC API v2).
    Top-level keys: aigateway, dashboard, workbenches, aipipelines, kserve,
      kueue, trainingoperator, trainer, ray, trustyai, modelregistry,
      feastoperator, llamastackoperator (deprecated), ogx, mlflowoperator,
      sparkoperator, mcplifecycleoperator.
    Subcomponent keys: models_as_a_service, batch_gateway,
      argo_workflows_controllers, nim, wva.
    Values: "Managed" or "Removed"; kueue supports "Unmanaged" or "Removed".
  EOT
  default     = {}

  validation {
    condition = length(setsubtract(toset(keys(var.openshift_ai_components)), toset([
      "aigateway",
      "models_as_a_service",
      "batch_gateway",
      "dashboard",
      "workbenches",
      "aipipelines",
      "argo_workflows_controllers",
      "kserve",
      "nim",
      "wva",
      "kueue",
      "trainingoperator",
      "trainer",
      "ray",
      "trustyai",
      "modelregistry",
      "feastoperator",
      "llamastackoperator",
      "ogx",
      "mlflowoperator",
      "sparkoperator",
      "mcplifecycleoperator",
    ]))) == 0
    error_message = "openshift_ai_components contains an unsupported RHOAI 3.5 component key."
  }

  validation {
    condition = alltrue([
      for component, state in var.openshift_ai_components :
      component == "kueue" ? contains(["Unmanaged", "Removed"], state) : contains(["Managed", "Removed"], state)
    ])
    error_message = "OpenShift AI component states must be Managed or Removed; kueue must be Unmanaged or Removed."
  }
}

variable "openshift_ai_bucket_name" {
  type        = string
  description = "S3 bucket name for RHOAI data connections. From gitops_resources module when create_s3=true."
  default     = ""
}

variable "openshift_ai_bucket_region" {
  type        = string
  description = "AWS region of the RHOAI S3 bucket."
  default     = ""
}

variable "openshift_ai_s3_endpoint" {
  type        = string
  description = "S3 endpoint hostname for RHOAI data connections."
  default     = ""
}

variable "openshift_ai_create_irsa" {
  type        = bool
  description = "Whether to annotate RHOAI service accounts with the IAM role for IRSA."
  default     = false
}

variable "openshift_ai_role_arn" {
  type        = string
  description = "IAM role ARN for RHOAI workloads (IRSA). Used to annotate service accounts for S3/ECR access."
  default     = ""
}

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for operator channel selection.
    
    This controls version-specific operator channels:
    
    | Operator        | OCP 4.16-4.18 | OCP 4.19+ |
    |-----------------|---------------|-----------|
    | Loki            | stable-6.2 EUS | 4.19: stable-6.5; 4.20-4.22: stable-6.6 |
    | Cluster Logging | stable-6.2 EUS | 4.19: stable-6.5; 4.20-4.22: stable-6.6 |
    | OADP            | stable        | stable    |
    | Virtualization  | stable        | stable    |
    | Web Terminal    | fast          | fast      |
    
    Operators using generic channels (stable/fast) auto-select versions.
    Only operators with version-specific channels need this calculation.
    
    Format: "4.XX" (e.g., "4.16", "4.20")
  EOT
  default     = "4.20"
}

variable "certmanager_operator_config" {
  description = "Red Hat OLM subscription and operand replica settings. stable-v1 tracks the latest supported catalog release; use a mirrored catalog in restricted environments."
  type = object({
    channel               = optional(string, "stable-v1")
    source                = optional(string, "redhat-operators")
    source_namespace      = optional(string, "openshift-marketplace")
    install_plan_approval = optional(string, "Automatic")
    controller_replicas   = optional(number, 2)
    webhook_replicas      = optional(number, 3)
    cainjector_replicas   = optional(number, 2)
  })
  default = {}
  validation {
    condition = contains(["Automatic", "Manual"], var.certmanager_operator_config.install_plan_approval) && alltrue([
      for replicas in [var.certmanager_operator_config.controller_replicas, var.certmanager_operator_config.webhook_replicas, var.certmanager_operator_config.cainjector_replicas] :
      replicas >= 1 && floor(replicas) == replicas
    ])
    error_message = "Approval must be Automatic or Manual, and replica counts must be positive integers."
  }
}

variable "certmanager_dns01_recursive_nameservers" {
  type        = list(string)
  description = "Optional approved DNS resolvers in host:port format. Empty uses cluster DNS; no public resolvers are forced."
  default     = []
}

variable "certmanager_dns01_recursive_nameservers_only" {
  type        = bool
  description = "Use only the configured recursive resolvers for DNS01 self-checks."
  default     = false
  validation {
    condition     = !var.certmanager_dns01_recursive_nameservers_only || length(var.certmanager_dns01_recursive_nameservers) > 0
    error_message = "Recursive-only DNS requires at least one approved resolver."
  }
}
