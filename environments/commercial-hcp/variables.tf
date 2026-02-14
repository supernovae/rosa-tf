#------------------------------------------------------------------------------
# ROSA HCP - Commercial AWS Variables
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "rhcs_client_id" {
  type        = string
  description = <<-EOT
    RHCS service account client ID for Commercial AWS.

    Create a service account at:
      https://console.redhat.com/iam/service-accounts

    The service account must have "OpenShift Cluster Manager" permissions.
    See: https://console.redhat.com/iam/user-access/users

    Set via environment variable (recommended):
      export TF_VAR_rhcs_client_id="your-client-id"

    Note: The offline OCM token is deprecated for commercial cloud.
    Service accounts are the recommended authentication method for
    both CI/CD pipelines and local workstation use.
  EOT
  sensitive   = false
}

variable "rhcs_client_secret" {
  type        = string
  description = <<-EOT
    RHCS service account client secret for Commercial AWS.

    Generated when creating a service account at:
      https://console.redhat.com/iam/service-accounts

    IMPORTANT: Save the client secret when created -- it is only
    shown once and cannot be retrieved later.

    Set via environment variable (recommended):
      export TF_VAR_rhcs_client_secret="your-client-secret"
  EOT
  sensitive   = true
}

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA HCP cluster (1-15 lowercase alphanumeric)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,13}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be 1-15 lowercase alphanumeric characters, may include hyphens."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for the cluster."
  default     = "us-east-1"

  validation {
    condition     = can(regex("^(us|eu|ap|sa|ca|me|af)-(north|south|east|west|central|northeast|southeast)-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS commercial region."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

#------------------------------------------------------------------------------
# OpenShift Version Configuration
#------------------------------------------------------------------------------

variable "openshift_version" {
  type        = string
  description = "OpenShift version for control plane (e.g., 4.20.10). Run 'rosa list versions' to see available."
  default     = "4.20.10"

  validation {
    condition     = can(regex("^4\\.[0-9]+\\.[0-9]+$", var.openshift_version))
    error_message = "OpenShift version must be in format X.Y.Z."
  }
}

variable "machine_pool_version" {
  type        = string
  description = <<-EOT
    OpenShift version for machine pools.
    
    Default: Same as openshift_version (control plane).
    
    For upgrades, HCP allows control plane and machine pools to be at
    different versions (machine pools must be within n-2 of control plane).
    
    Upgrade workflow:
      1. Update openshift_version → control plane upgrades
      2. Update machine_pool_version → machine pools upgrade
    
    Set to null to use openshift_version (default, keeps in sync).
  EOT
  default     = null

  validation {
    condition     = var.machine_pool_version == null || can(regex("^4\\.[0-9]+\\.[0-9]+$", var.machine_pool_version))
    error_message = "Machine pool version must be null or in format X.Y.Z."
  }
}

variable "channel_group" {
  type        = string
  description = "Update channel: stable, fast, candidate, or eus."
  default     = "stable"

  validation {
    condition     = contains(["stable", "fast", "candidate", "eus"], var.channel_group)
    error_message = "Channel must be: stable, fast, candidate, or eus."
  }
}

variable "upgrade_acknowledgements_for" {
  type        = string
  description = <<-EOT
    Acknowledge upgrade to this version when breaking changes exist.
    Required when upgrading to versions with removed Kubernetes APIs.
    Example: "4.17" to acknowledge upgrade to 4.17.x
    Leave empty/null for normal operations.
  EOT
  default     = null
}

variable "skip_version_drift_check" {
  type        = bool
  description = "Skip version drift validation between control plane and machine pools."
  default     = false
}

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones. Defaults to auto-select."
  default     = null

  validation {
    condition     = var.availability_zones == null || try(length(var.availability_zones) >= 1 && length(var.availability_zones) <= 3, false)
    error_message = "Must specify 1-3 availability zones."
  }
}

variable "multi_az" {
  type        = bool
  description = "Deploy across multiple availability zones (true for production)."
  default     = false
}

variable "egress_type" {
  type        = string
  description = <<-EOT
    Type of internet egress for the private subnets:
    - "nat": Creates public subnets, Internet Gateway, and NAT gateways (standalone deployment)
    - "tgw": No public infrastructure; egress via Transit Gateway (requires transit_gateway_id)
    - "proxy": No public infrastructure; egress via HTTP/HTTPS proxy configured in cluster
    - "none": No public infrastructure, no egress (zero-egress/air-gapped, HCP only)
    
    Note: When zero_egress = true, egress_type is automatically set to "none".
  EOT
  default     = "nat"

  validation {
    condition     = contains(["nat", "tgw", "proxy"], var.egress_type)
    error_message = "egress_type must be one of: nat, tgw, proxy"
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit Gateway ID for egress routing (when egress_type = 'tgw')."
  default     = null
}

variable "transit_gateway_route_cidr" {
  type        = string
  description = "CIDR block to route via Transit Gateway (typically 0.0.0.0/0 for internet egress)."
  default     = "0.0.0.0/0"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets. Auto-calculated if null."
  default     = null
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets. Auto-calculated if null."
  default     = null
}

#------------------------------------------------------------------------------
# BYO-VPC Configuration (Optional)
#
# Deploy into an existing VPC instead of creating a new one.
# When existing_vpc_id is set, the VPC module is skipped entirely.
# The number of private subnets determines cluster topology:
#   - 1 subnet  = single-AZ cluster
#   - 3 subnets = multi-AZ cluster
#
# See docs/BYO-VPC.md for CIDR planning and multi-cluster guidance.
#------------------------------------------------------------------------------

variable "existing_vpc_id" {
  type        = string
  description = <<-EOT
    ID of an existing VPC to deploy into (BYO-VPC).
    When set, skips VPC creation and uses provided subnet IDs.
    
    The VPC must have:
    - DNS hostnames enabled
    - DNS resolution enabled
    - Appropriate tags for ROSA (kubernetes.io/cluster/<name>)
  EOT
  default     = null
}

variable "existing_private_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    Private subnet IDs in the existing VPC. Required when existing_vpc_id is set.

    The number of subnets determines cluster topology:
      - 1 subnet  = single-AZ cluster (dev/test)
      - 3 subnets = multi-AZ cluster (production HA)

    Each subnet must be in a different AZ for multi-AZ deployments.
    Subnets must be tagged with: kubernetes.io/role/internal-elb = 1
  EOT
  default     = null

  validation {
    condition     = var.existing_private_subnet_ids == null ? true : contains([1, 3], length(var.existing_private_subnet_ids))
    error_message = "Provide 1 subnet (single-AZ) or 3 subnets (multi-AZ). Other counts are not supported by ROSA."
  }
}

variable "existing_public_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    Public subnet IDs in the existing VPC. Required for public clusters with BYO-VPC.

    Must match the same AZ count as existing_private_subnet_ids.
    Subnets must be tagged with: kubernetes.io/role/elb = 1
  EOT
  default     = null
}

variable "pod_cidr" {
  type        = string
  description = <<-EOT
    CIDR block for pod network.
    Default is safe for a single cluster. For multi-cluster in the same VPC,
    each cluster needs a unique pod CIDR to avoid routing conflicts.
    
    Examples for multi-cluster:
      Cluster 1: 10.128.0.0/14 (default)
      Cluster 2: 10.132.0.0/14
  EOT
  default     = "10.128.0.0/14"
}

variable "service_cidr" {
  type        = string
  description = <<-EOT
    CIDR block for service network.
    Default is safe for a single cluster. For multi-cluster in the same VPC,
    each cluster needs a unique service CIDR.
    
    Examples for multi-cluster:
      Cluster 1: 172.30.0.0/16 (default)
      Cluster 2: 172.31.0.0/16
  EOT
  default     = "172.30.0.0/16"
}

variable "host_prefix" {
  type        = number
  description = "Subnet prefix length assigned to each node for pod IPs."
  default     = 23
}

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

variable "private_cluster" {
  type        = bool
  description = <<-EOT
    Deploy as a private cluster (no public API/ingress endpoints).

    - true (default): API and ingress only accessible from within VPC
      * Requires jump host or VPN for access
      * More secure for production workloads

    - false: Public API and ingress endpoints
      * Direct access from internet
      * Simpler setup for development

    Note: HCP control plane connectivity ALWAYS uses AWS PrivateLink
    (workers connect to Red Hat-managed control plane via PrivateLink).
    This setting only controls whether API/ingress endpoints are public.
  EOT
  default     = true
}

variable "zero_egress" {
  type        = bool
  description = <<-EOT
    Enable zero-egress mode for fully air-gapped operation (HCP only).

    When enabled:
    - Cluster pulls OpenShift images from Red Hat's regional ECR
    - No NAT gateway or internet gateway required
    - Custom operators must be mirrored to your own ECR

    Requirements:
    - private_cluster must be true
    - VPN or jump host for cluster access
    - Operator mirroring workflow (see docs/ZERO-EGRESS.md)
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# ECR Configuration (Optional)
#------------------------------------------------------------------------------

variable "create_ecr" {
  type        = bool
  description = <<-EOT
    Create an ECR repository for container images.
    
    Use cases:
    - Private container registry for custom application images
    - Operator mirroring for zero-egress clusters
    
    When enabled, automatically attaches ECR pull policy to worker nodes.
  EOT
  default     = false
}

variable "ecr_repository_name" {
  type        = string
  description = "Custom ECR repository name. Defaults to {cluster_name}-registry."
  default     = ""
}

variable "ecr_prevent_destroy" {
  type        = bool
  description = <<-EOT
    Prevent ECR repository from being destroyed with the cluster.
    
    When true:
    - Repository survives terraform destroy of the cluster
    - Useful for shared registries or preserving images across cluster rebuilds
    
    To destroy when prevent_destroy = true:
      1. Set ecr_prevent_destroy = false in tfvars
      2. Run: terraform destroy -target=module.ecr
  EOT
  default     = false
}

variable "ecr_create_vpc_endpoints" {
  type        = bool
  description = <<-EOT
    Create VPC endpoints for ECR (ecr.api and ecr.dkr).

    Defaults to true because:
    1. Cost efficiency - Avoids NAT Gateway egress charges for image pulls
    2. Required for zero-egress - Clusters without internet need private ECR access
    3. Security - All ECR traffic stays within AWS private network

    Set to false if using shared VPC with existing ECR endpoints.
  EOT
  default     = true
}

variable "compute_machine_type" {
  type        = string
  description = "EC2 instance type for worker nodes."
  default     = "m5.xlarge"
}

variable "worker_node_count" {
  type        = number
  description = "Number of worker nodes in default pool."
  default     = 2

  validation {
    condition     = var.worker_node_count >= 2
    error_message = "HCP requires at least 2 worker nodes."
  }
}

#------------------------------------------------------------------------------
# KMS Encryption Configuration
#
# Two separate keys with independent modes for blast radius containment:
# - cluster_kms_*: For ROSA workers and etcd ONLY
# - infra_kms_*: For jump host, CloudWatch, S3/OADP, VPN ONLY
#------------------------------------------------------------------------------

variable "cluster_kms_mode" {
  type        = string
  description = <<-EOT
    Cluster KMS key management mode:
    - "provider_managed" (DEFAULT): Use AWS managed aws/ebs key - simplest, no KMS costs
    - "create": Terraform creates a customer-managed KMS key
    - "existing": Use an existing KMS key ARN (set cluster_kms_key_arn)

    This key is used ONLY for ROSA-managed resources (workers, etcd).
    All modes provide encryption at rest.
  EOT
  default     = "provider_managed"

  validation {
    condition     = contains(["provider_managed", "create", "existing"], var.cluster_kms_mode)
    error_message = "cluster_kms_mode must be one of: provider_managed, create, existing"
  }
}

variable "cluster_kms_key_arn" {
  type        = string
  description = "ARN of existing KMS key for cluster. Required when cluster_kms_mode = 'existing'."
  default     = null
}

variable "infra_kms_mode" {
  type        = string
  description = <<-EOT
    Infrastructure KMS key management mode:
    - "provider_managed" (DEFAULT): Use AWS managed aws/ebs key - simplest, no KMS costs
    - "create": Terraform creates a customer-managed KMS key
    - "existing": Use an existing KMS key ARN (set infra_kms_key_arn)

    This key is used ONLY for non-ROSA resources:
    - Jump host EBS volumes
    - CloudWatch log encryption
    - S3 bucket encryption (OADP, backups)
    - VPN connection logs

    IMPORTANT: Separate from cluster KMS for blast radius containment.
  EOT
  default     = "provider_managed"

  validation {
    condition     = contains(["provider_managed", "create", "existing"], var.infra_kms_mode)
    error_message = "infra_kms_mode must be one of: provider_managed, create, existing"
  }
}

variable "infra_kms_key_arn" {
  type        = string
  description = "ARN of existing KMS key for infrastructure. Required when infra_kms_mode = 'existing'."
  default     = null
}

variable "etcd_encryption" {
  type        = bool
  description = <<-EOT
    Enable etcd encryption at rest using customer-managed KMS key.
    Only applies when cluster_kms_mode = "create" or "existing".

    When cluster_kms_mode = "provider_managed", etcd uses AWS managed encryption.

    Recommended: true for production workloads with sensitive data.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# Admin User Configuration
#------------------------------------------------------------------------------

variable "create_admin_user" {
  type        = bool
  description = "Create htpasswd admin user."
  default     = true
}

variable "admin_username" {
  type        = string
  description = "Admin username."
  default     = "cluster-admin"
}

#------------------------------------------------------------------------------
# Additional Machine Pools Configuration
#
# Generic list of machine pools for any workload type.
# See docs/MACHINE-POOLS.md for examples: GPU, bare metal, ARM/Graviton, etc.
#------------------------------------------------------------------------------

variable "machine_pools" {
  type = list(object({
    name          = string
    instance_type = string
    replicas      = optional(number, 2)
    autoscaling = optional(object({
      enabled = bool
      min     = number
      max     = number
    }))
    labels = optional(map(string), {})
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string
    })), [])
    subnet_id = optional(string)
  }))

  description = <<-EOT
    List of additional machine pools to create.
    
    Each pool object supports:
    - name: Pool name (required)
    - instance_type: EC2 instance type (required)
    - replicas: Fixed replica count (default: 2, ignored if autoscaling enabled)
    - autoscaling: { enabled = bool, min = number, max = number }
    - labels: Map of node labels for workload targeting
    - taints: List of taints for workload isolation
    - subnet_id: Override default subnet
    
    Examples in docs/MACHINE-POOLS.md:
    - GPU pools (NVIDIA g4dn, p3, p4d)
    - Bare metal pools (m5.metal for OpenShift Virtualization)
    - ARM/Graviton pools (m6g, m7g for cost optimization)
    - High memory pools (r5, x2idn)
    
    Note: HCP spot instances coming soon. See Classic for current spot support.
  EOT

  default = []
}

#------------------------------------------------------------------------------
# Cluster Autoscaler Configuration
#
# The cluster autoscaler controls cluster-wide scaling behavior.
# For ROSA HCP, it's fully managed by Red Hat (runs with control plane).
#
# Both cluster autoscaler AND machine pool autoscaling must be enabled
# for automatic scaling to work.
#------------------------------------------------------------------------------

variable "cluster_autoscaler_enabled" {
  type        = bool
  description = <<-EOT
    Enable the cluster autoscaler for automatic cluster sizing.
    
    The cluster autoscaler:
    - Adds nodes when pods can't be scheduled due to insufficient resources
    - Removes underutilized nodes (default 50% utilization threshold)
    - Only affects machine pools that have autoscaling enabled
  EOT
  default     = false
}

variable "autoscaler_max_nodes_total" {
  type        = number
  description = <<-EOT
    Maximum number of nodes across all autoscaling machine pools.
    Nodes in non-autoscaling pools are NOT counted toward this limit.
  EOT
  default     = 100
}

variable "autoscaler_max_node_provision_time" {
  type        = string
  description = <<-EOT
    Maximum time the autoscaler waits for a node to become ready.
    Format: duration string (e.g., "15m", "30m")
  EOT
  default     = "25m"
}

variable "autoscaler_max_pod_grace_period" {
  type        = number
  description = "Graceful termination time in seconds for pods during scale down."
  default     = 600
}

variable "autoscaler_pod_priority_threshold" {
  type        = number
  description = <<-EOT
    Priority threshold for pod scheduling.
    Pods below this priority won't trigger scale up or prevent scale down.
  EOT
  default     = -10
}

#------------------------------------------------------------------------------
# Jump Host Configuration
#------------------------------------------------------------------------------

variable "create_jumphost" {
  type        = bool
  description = "Create SSM-enabled jump host for private cluster access."
  default     = false
}

variable "jumphost_instance_type" {
  type        = string
  description = "EC2 instance type for the jump host."
  default     = "t3.micro"
}

variable "jumphost_ami_id" {
  type        = string
  description = "AMI ID for the jump host. If null, uses latest Amazon Linux 2023."
  default     = null
}

#------------------------------------------------------------------------------
# Client VPN Configuration
# Note: The client-vpn module generates its own certificates automatically
#------------------------------------------------------------------------------

variable "create_client_vpn" {
  type        = bool
  description = <<-EOT
    Create AWS Client VPN endpoint for direct cluster access.
    The module generates certificates automatically - no ACM setup required.
    
    Cost: ~$116/month. Create/destroy takes 15-25 minutes.
    Consider using jump host (SSM) for cost savings.
  EOT
  default     = false
}

variable "vpn_client_cidr_block" {
  type        = string
  description = <<-EOT
    CIDR block for VPN client IP addresses. Must not overlap with VPC CIDR.
    Minimum /22 (1024 addresses). AWS reserves half for HA.
  EOT
  default     = "10.100.0.0/22"
}

variable "vpn_split_tunnel" {
  type        = bool
  description = "Enable split tunnel (only VPC traffic through VPN). Recommended: true."
  default     = true
}

variable "vpn_session_timeout_hours" {
  type        = number
  description = "VPN session timeout in hours (8-24)."
  default     = 12
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}

#------------------------------------------------------------------------------
# GitOps Configuration
#------------------------------------------------------------------------------

variable "install_gitops" {
  type        = bool
  description = <<-EOT
    Install OpenShift GitOps operator and layers framework.
    
    RECOMMENDED: Deploy in two stages for reliability:
    
      Stage 1 - Infrastructure (default):
        terraform apply -var-file=dev.tfvars
        # Creates VPC, IAM, ROSA cluster
    
      Stage 2 - GitOps (when ready):
        terraform apply -var-file=dev.tfvars -var="install_gitops=true"
        # Installs GitOps operator and configured layers
    
    For zero-egress clusters: Mirror required operators to ECR before Stage 2.
    See docs/DISCONNECTED-OPERATIONS.md for operator mirroring guide.
    
    Set to false when destroying to skip GitOps connectivity checks:
      terraform destroy -var="install_gitops=false" -var-file=dev.tfvars
  EOT
  default     = false
}

variable "gitops_repo_url" {
  type        = string
  description = <<-EOT
    Git repository URL for ADDITIONAL custom resources to deploy via ArgoCD.
    This does NOT replace the built-in layers (monitoring, OADP, etc.) which
    are always managed by Terraform. Use this for your own static manifests
    (projects, quotas, RBAC, apps). When provided, an ArgoCD Application
    is created to sync from this repo.
  EOT
  default     = null
}

variable "gitops_repo_path" {
  type        = string
  description = "Path within repository for GitOps manifests."
  default     = null
}

variable "gitops_repo_revision" {
  type        = string
  description = "Git revision (branch, tag, commit) for GitOps repository."
  default     = null
}



variable "gitops_oauth_url" {
  type        = string
  description = <<-EOT
    OAuth server URL for GitOps authentication (optional).
    
    If not set, automatically derived from cluster API URL:
      API URL:   https://api.<cluster>.<domain>:6443
      OAuth URL: https://oauth-openshift.apps.<cluster>.<domain>
    
    Set this if:
    - Using HCP with external authentication
    - Older OpenShift version with different OAuth routing
    - Custom OAuth configuration
    
    Discovery: oc get route -n openshift-authentication oauth-openshift -o jsonpath='{.spec.host}'
  EOT
  default     = null
}

variable "gitops_cluster_token" {
  type        = string
  description = <<-EOT
    Pre-provided cluster token for GitOps authentication (optional).
    
    If set, skips OAuth token retrieval and uses this token directly.
    Useful for HCP clusters with external auth (OIDC, LDAP) where
    htpasswd IDP is not available.
    
    To obtain: oc login <cluster> && oc whoami -t
  EOT
  default     = null
  sensitive   = true
}

variable "enable_layer_terminal" {
  type        = bool
  description = "Enable Web Terminal layer."
  default     = false
}

variable "enable_layer_oadp" {
  type        = bool
  description = "Enable OADP (backup) layer."
  default     = false
}

variable "oadp_backup_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain backups.
    Controls both Velero backup TTL and S3 lifecycle rules.
  EOT
  default     = 30
}

variable "enable_layer_virtualization" {
  type        = bool
  description = "Enable Virtualization layer."
  default     = false
}

variable "enable_layer_monitoring" {
  type        = bool
  description = <<-EOT
    Enable the Monitoring and Logging layer.
    Installs Prometheus with persistent storage and Loki with S3 backend.
    Creates S3 bucket and IAM role for Loki log storage.
  EOT
  default     = false
}

variable "monitoring_loki_size" {
  type        = string
  description = <<-EOT
    LokiStack deployment size. Controls resource allocation for all Loki components.
    
    Available sizes:
    - 1x.extra-small: Development/testing (default, ~2 vCPU, 4GB per component)
    - 1x.small: Small production (~4 vCPU, 8GB per component, requires 6+ nodes)
    - 1x.medium: Medium production (~8 vCPU, 16GB per component)
    
    IMPORTANT: 1x.small and larger require significant cluster resources.
    For dev environments with m5.xlarge nodes, use 1x.extra-small.
  EOT
  default     = "1x.extra-small"
}

variable "monitoring_retention_days" {
  type        = number
  description = <<-EOT
    Retention period for metrics and logs in days.
    Controls both Prometheus retention and Loki compactor retention.
    Recommended: 7 for dev, 30 for production.
  EOT
  default     = 30
}

variable "monitoring_prometheus_storage_size" {
  type        = string
  description = <<-EOT
    Size of Prometheus persistent volume.
    Recommended: 50Gi for 7-day retention, 100Gi for 30-day retention.
  EOT
  default     = "100Gi"
}

variable "monitoring_storage_class" {
  type        = string
  description = "StorageClass for Prometheus and Loki PVCs."
  default     = "gp3-csi"
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
# Cert-Manager Layer Configuration
#------------------------------------------------------------------------------

variable "enable_layer_certmanager" {
  type        = bool
  description = <<-EOT
    Enable the Cert-Manager layer for automated certificate lifecycle management.
    
    Installs the OpenShift cert-manager operator and configures Let's Encrypt
    with DNS01/Route53 challenge for automatic certificate provisioning.
    
    IMPORTANT: Requires outbound internet access for ACME challenges.
    Cannot be used on zero-egress clusters.
  EOT
  default     = false
}

variable "certmanager_hosted_zone_id" {
  type        = string
  description = <<-EOT
    Route53 hosted zone ID for DNS01 challenges.
    Required when not creating a new hosted zone.
  EOT
  default     = ""
}

variable "certmanager_hosted_zone_domain" {
  type        = string
  description = <<-EOT
    Domain for the Route53 hosted zone.
    Required when creating a new hosted zone (certmanager_create_hosted_zone = true).
    Example: "apps.example.com"
  EOT
  default     = ""
}

variable "certmanager_create_hosted_zone" {
  type        = bool
  description = <<-EOT
    Whether to create a new Route53 hosted zone for cert-manager.
    If false, provide certmanager_hosted_zone_id for an existing zone.
  EOT
  default     = false
}

variable "certmanager_enable_dnssec" {
  type        = bool
  description = <<-EOT
    Enable DNSSEC signing on the cert-manager Route53 hosted zone.
    Only applies when certmanager_create_hosted_zone = true.
    
    DNSSEC protects against DNS spoofing and cache poisoning.
    After enabling, add the DS record from outputs to your domain registrar
    to complete the chain of trust.
  EOT
  default     = true
}

variable "certmanager_enable_query_logging" {
  type        = bool
  description = <<-EOT
    Enable DNS query logging for the cert-manager Route53 hosted zone.
    Only applies when certmanager_create_hosted_zone = true.

    IMPORTANT: For Commercial AWS, Route53 query logging requires the
    CloudWatch log group in us-east-1. Set to false for other regions.
    For GovCloud, works in any deployment region.
  EOT
  default     = true
}

variable "certmanager_acme_email" {
  type        = string
  description = <<-EOT
    Email address for Let's Encrypt ACME registration.
    Let's Encrypt sends certificate expiry notifications to this address.
  EOT
  default     = ""
}

variable "certmanager_certificate_domains" {
  type = list(object({
    name        = string
    namespace   = string
    secret_name = string
    domains     = list(string)
  }))
  description = <<-EOT
    List of Certificate resources to create via cert-manager.
    Each entry requests a TLS certificate from Let's Encrypt.
    
    Example:
      certmanager_certificate_domains = [
        {
          name        = "apps-wildcard"
          namespace   = "openshift-ingress"
          secret_name = "custom-apps-default-cert"
          domains     = ["*.apps.example.com"]
        }
      ]
  EOT
  default     = []
}

variable "certmanager_enable_routes_integration" {
  type        = bool
  description = <<-EOT
    Enable the cert-manager OpenShift Routes integration.
    When enabled, annotate Routes for automatic TLS provisioning:
      oc annotate route <name> cert-manager.io/issuer-kind=ClusterIssuer cert-manager.io/issuer-name=letsencrypt-production
  EOT
  default     = true
}

variable "certmanager_ingress_enabled" {
  type        = bool
  description = <<-EOT
    Create a custom IngressController for the cert-manager domain.
    When true, a scoped IngressController is created with its own NLB,
    keeping custom domain traffic separate from the default ROSA ingress.
  EOT
  default     = true
}

variable "certmanager_ingress_domain" {
  type        = string
  description = <<-EOT
    Domain the custom IngressController serves (its spec.domain).
    When empty (default), auto-derives "apps.<hosted_zone_domain>".
    Override to serve routes on a different subdomain or the root domain.
    Examples: "apps.example.com", "example.com", "dev.example.com"
  EOT
  default     = ""
}

variable "certmanager_ingress_visibility" {
  type        = string
  description = <<-EOT
    Visibility of the custom ingress NLB: "private" or "public".
    Default: "private" (internal NLB, accessible within VPC / via VPN).
  EOT
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

#------------------------------------------------------------------------------
# Virtualization Layer Configuration
#------------------------------------------------------------------------------

variable "virt_node_selector" {
  type        = map(string)
  description = <<-EOT
    Node selector for OpenShift Virtualization components.
    Use to place virt-controller, virt-api, and VMs on dedicated nodes.
    Example: { "node-role.kubernetes.io/virtualization" = "" }
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
# Debug / Timing
#------------------------------------------------------------------------------

variable "enable_timing" {
  type        = bool
  description = <<-EOT
    Enable deployment timing capture.
    When true, outputs show start time, end time, and total duration.
    Useful for debugging and performance analysis.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# IAM Configuration (Account Roles)
#
# ROSA HCP uses ACCOUNT-LEVEL roles that are shared across clusters.
# Account roles must be created BEFORE deploying an HCP cluster.
#
# Create account roles via:
#   cd environments/account-hcp && terraform apply -var-file=commercial.tfvars
# Or:
#   rosa create account-roles --hosted-cp --mode auto
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

variable "account_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for account IAM roles.
    Default is "ManagedOpenShift" to match ROSA CLI convention.
    
    Role names: {prefix}-HCP-ROSA-{Installer|Support|Worker}-Role
  EOT
  default     = "ManagedOpenShift"
}

variable "installer_role_arn" {
  type        = string
  description = "Explicit installer role ARN (overrides discovery). Only used when create_account_roles = false."
  default     = null
}

variable "support_role_arn" {
  type        = string
  description = "Explicit support role ARN (overrides discovery). Only used when create_account_roles = false."
  default     = null
}

variable "worker_role_arn" {
  type        = string
  description = "Explicit worker role ARN (overrides discovery). Only used when create_account_roles = false."
  default     = null
}

#------------------------------------------------------------------------------
# OIDC Configuration
#
# Three modes are supported for OIDC (operator role authentication):
# 1. Managed (default): Red Hat hosts OIDC, created per-cluster
# 2. Managed (shared): Use pre-created managed OIDC config
# 3. Unmanaged: Customer hosts OIDC in their AWS account
#
# See docs/OIDC.md for detailed documentation.
#------------------------------------------------------------------------------

variable "create_oidc_config" {
  type        = bool
  description = <<-EOT
    Create a new OIDC configuration.
    
    - true (default): Create new OIDC config (managed or unmanaged based on managed_oidc)
    - false: Use existing OIDC config (requires oidc_config_id and oidc_endpoint_url)
    
    Set to false when sharing OIDC config across clusters or using pre-created config.
  EOT
  default     = true
}

variable "oidc_config_id" {
  type        = string
  description = <<-EOT
    Existing OIDC configuration ID.
    Required when create_oidc_config = false.
  EOT
  default     = null
}

variable "oidc_endpoint_url" {
  type        = string
  description = <<-EOT
    Existing OIDC endpoint URL (without https://).
    Required when create_oidc_config = false.
  EOT
  default     = null
}

variable "managed_oidc" {
  type        = bool
  description = <<-EOT
    Use Red Hat managed OIDC configuration.
    Only applies when create_oidc_config = true.
    
    - true (default): Red Hat hosts OIDC provider and manages private key
    - false: Customer hosts OIDC in their AWS account (unmanaged)
  EOT
  default     = true
}

variable "oidc_private_key_secret_arn" {
  type        = string
  description = <<-EOT
    ARN of AWS Secrets Manager secret containing the OIDC private key.
    Required when create_oidc_config = true and managed_oidc = false.
  EOT
  default     = null
}

variable "installer_role_arn_for_oidc" {
  type        = string
  description = <<-EOT
    ARN of installer role for unmanaged OIDC creation.
    Required when create_oidc_config = true and managed_oidc = false.
  EOT
  default     = null
}

#------------------------------------------------------------------------------
# External Authentication (HCP Only)
#
# Enables direct integration with external OIDC identity providers for user
# authentication, replacing the built-in OpenShift OAuth server.
#
# IMPORTANT: Cannot be changed after cluster creation.
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
    
    See docs/OIDC.md for external authentication setup guide.
  EOT
  default     = false
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
#
# See docs/SECURITY-GROUPS.md for detailed documentation.
#------------------------------------------------------------------------------

variable "additional_security_groups_enabled" {
  type        = bool
  description = <<-EOT
    Enable additional security groups for cluster nodes.
    
    When true, the module will create or use security groups based on
    the configuration below.
    
    IMPORTANT: Can only be set at cluster creation time.
  EOT
  default     = false
}

variable "use_intra_vpc_security_group_template" {
  type        = bool
  description = <<-EOT
    Create a template security group allowing intra-VPC traffic.
    
    WARNING: This creates permissive rules allowing all traffic within the VPC CIDR.
    While convenient for development, consider more restrictive rules for production.
    
    The template creates rules allowing:
    - All TCP traffic from VPC CIDR
    - All UDP traffic from VPC CIDR
    - All ICMP traffic from VPC CIDR
    
    Requires additional_security_groups_enabled = true.
  EOT
  default     = false
}

variable "existing_compute_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of existing security group IDs to attach to compute/worker nodes.
    
    These are applied in addition to any security groups created by the
    intra-VPC template or custom rules.
    
    Example: ["sg-abc123", "sg-def456"]
  EOT
  default     = []
}

variable "compute_security_group_rules" {
  type = object({
    ingress = optional(list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
      self            = optional(bool, false)
    })), [])
    egress = optional(list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
      self            = optional(bool, false)
    })), [])
  })
  description = <<-EOT
    Custom security group rules for compute/worker nodes.
    
    Example:
    compute_security_group_rules = {
      ingress = [
        {
          description = "Allow HTTPS from corporate network"
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = ["10.100.0.0/16"]
        }
      ]
      egress = []
    }
  EOT
  default = {
    ingress = []
    egress  = []
  }
}

variable "terraform_sa_name" {
  type        = string
  description = "Name of the Kubernetes ServiceAccount for Terraform cluster management."
  default     = "terraform-operator"
}

variable "skip_k8s_destroy" {
  type        = bool
  description = "Set true before terraform destroy to skip K8s resource deletion. See docs/OPERATIONS.md."
  default     = false
}
