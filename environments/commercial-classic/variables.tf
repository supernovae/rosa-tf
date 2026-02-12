#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster. Must be unique within the account."

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,13}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be 1-15 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

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

#------------------------------------------------------------------------------
# AWS Configuration
#------------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS Commercial region for deployment."
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g., us-east-1, eu-west-1)."
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

variable "multi_az" {
  type        = bool
  description = <<-EOT
    Deploy cluster across multiple availability zones.
    
    - true (default): Production pattern with 3 AZs for high availability
    - false: Development/test pattern with single AZ (lower cost)
  EOT
  default     = true
}

variable "availability_zones" {
  type        = list(string)
  description = <<-EOT
    List of availability zones for the cluster.
    - Multi-AZ: Specify 3 AZs or leave null to auto-select
    - Single-AZ: Specify 1 AZ or leave null to auto-select first available
  EOT
  default     = null

  validation {
    condition = var.availability_zones == null || try(
      length(var.availability_zones) == 1 || length(var.availability_zones) == 3, false
    )
    error_message = "Must specify 1 AZ (single-AZ) or 3 AZs (multi-AZ), or leave null."
  }
}

#------------------------------------------------------------------------------
# Cluster Access Configuration
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

    Note: Private clusters use AWS PrivateLink for Red Hat SRE access.
    Public clusters allow SRE access via the public API endpoint.
  EOT
  default     = true
}

#------------------------------------------------------------------------------
# OpenShift Configuration
#------------------------------------------------------------------------------

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for the cluster (x.y.z format).
    
    To see available versions, run:
      rosa list versions --channel-group stable
  EOT
  default     = "4.20.10"

  validation {
    condition     = can(regex("^4\\.[0-9]+\\.[0-9]+$", var.openshift_version))
    error_message = "OpenShift version must be in x.y.z format (e.g., 4.20.10)."
  }
}

variable "channel_group" {
  type        = string
  description = <<-EOT
    Update channel group for the cluster.
    - "stable": Standard channel for all releases
    - "eus": Extended Update Support for even-numbered releases
  EOT
  default     = "stable"

  validation {
    condition     = contains(["eus", "stable"], var.channel_group)
    error_message = "Channel group must be 'eus' or 'stable'."
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

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "fips" {
  type        = bool
  description = <<-EOT
    Enable FIPS 140-2 validated cryptographic modules.
    
    - true: Required for FedRAMP/regulated workloads
    - false (default): Standard cryptographic modules
    
    Note: Cannot be changed after cluster creation.
  EOT
  default     = false
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
    Enable additional etcd encryption at rest using customer-managed KMS key.
    Only applies when cluster_kms_mode = "create" or "existing".
    
    Note: ROSA Classic already encrypts EBS at rest (etcd lives on EBS).
    This option adds an additional encryption layer specifically for etcd data.
    
    Recommended: Enable for strict compliance requirements.
  EOT
  default     = false
}

#------------------------------------------------------------------------------
# VPC Configuration
#------------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets. If null, auto-calculated."
  default     = null
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets. If null, auto-calculated."
  default     = null
}

variable "egress_type" {
  type        = string
  description = <<-EOT
    Type of internet egress for the private subnets:
    - "nat": NAT gateways (default)
    - "tgw": Transit Gateway
    - "proxy": HTTP/HTTPS proxy
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
  description = "CIDR block to route via Transit Gateway."
  default     = "0.0.0.0/0"
}

variable "enable_vpc_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs."
  default     = false
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Days to retain VPC flow logs."
  default     = 30
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

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

variable "compute_machine_type" {
  type        = string
  description = "EC2 instance type for worker nodes."
  default     = "m5.xlarge"
}

variable "worker_node_count" {
  type        = number
  description = "Number of worker nodes (minimum 2 for single-AZ, 3 for multi-AZ)."
  default     = 3

  validation {
    condition     = var.worker_node_count >= 2
    error_message = "Worker node count must be at least 2."
  }
}

variable "worker_disk_size" {
  type        = number
  description = "Root disk size in GB for worker nodes."
  default     = 300
}

#------------------------------------------------------------------------------
# Cluster Autoscaler Configuration
# Controls cluster-wide autoscaling behavior
#------------------------------------------------------------------------------

variable "cluster_autoscaler_enabled" {
  type        = bool
  description = <<-EOT
    Enable the cluster autoscaler.
    Configures cluster-wide autoscaling behavior including scale-down thresholds,
    timing, and resource limits.
    
    Note: Machine pool autoscaling must also be enabled for pools to actually scale.
  EOT
  default     = false
}

variable "autoscaler_max_nodes_total" {
  type        = number
  description = <<-EOT
    Maximum total nodes in cluster (control plane + all workers).
    
    Classic: Account for 3 control plane + 3 infra + max workers
    Default 100 provides headroom for most deployments.
  EOT
  default     = 100
}

variable "autoscaler_scale_down_enabled" {
  type        = bool
  description = "Enable automatic scale down of underutilized nodes."
  default     = true
}

variable "autoscaler_scale_down_utilization_threshold" {
  type        = string
  description = "Node utilization threshold for scale down (0-1). Default 0.5 = scale down if < 50% utilized."
  default     = "0.5"
}

variable "autoscaler_scale_down_delay_after_add" {
  type        = string
  description = "Delay after adding a node before considering it for scale down."
  default     = "10m"
}

variable "autoscaler_scale_down_unneeded_time" {
  type        = string
  description = "How long a node must be unneeded before eligible for scale down."
  default     = "10m"
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
  description = "Host prefix for node subnets."
  default     = 23
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
# IAM Configuration (Cluster-Scoped)
#
# ROSA Classic uses cluster-scoped IAM roles:
# - Each cluster has its own set of account roles
# - Roles are named using cluster_name as the default prefix
# - Destroying a cluster cleanly removes its IAM roles
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

variable "account_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for account IAM roles.
    Defaults to cluster_name for cluster-scoped roles.
    
    Role names will be: {prefix}-Installer-Role, {prefix}-Support-Role, etc.
  EOT
  default     = null
}

variable "operator_role_prefix" {
  type        = string
  description = <<-EOT
    Prefix for operator IAM roles.
    Defaults to cluster_name for cluster-scoped roles.
  EOT
  default     = null
}

variable "path" {
  type        = string
  description = "IAM path for roles."
  default     = "/"
}

variable "permissions_boundary" {
  type        = string
  description = "ARN of the permissions boundary for IAM roles."
  default     = ""
}

variable "kms_key_deletion_window" {
  type        = number
  description = "Days before KMS keys are deleted (7-30). Only applies when cluster_kms_mode or infra_kms_mode = 'create'."
  default     = 30
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
    - Mirror public images for air-gapped or compliance scenarios
    
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

#------------------------------------------------------------------------------
# Jump Host Configuration (Optional)
#------------------------------------------------------------------------------

variable "create_jumphost" {
  type        = bool
  description = "Create SSM-enabled jump host for cluster access."
  default     = false
}

variable "jumphost_instance_type" {
  type        = string
  description = "Instance type for jump host."
  default     = "t3.micro"
}

variable "jumphost_ami_id" {
  type        = string
  description = "AMI ID for jump host (null = latest Amazon Linux 2023)."
  default     = null
}

#------------------------------------------------------------------------------
# Client VPN Configuration (Optional)
#------------------------------------------------------------------------------

variable "create_client_vpn" {
  type        = bool
  description = "Create AWS Client VPN endpoint."
  default     = false
}

variable "vpn_client_cidr_block" {
  type        = string
  description = "CIDR block for VPN clients."
  default     = "10.100.0.0/22"
}

variable "vpn_split_tunnel" {
  type        = bool
  description = "Enable split tunnel (only VPC traffic through VPN)."
  default     = true
}

variable "vpn_session_timeout_hours" {
  type        = number
  description = "VPN session timeout in hours."
  default     = 12
}

#------------------------------------------------------------------------------
# Custom Ingress Configuration (Optional)
#------------------------------------------------------------------------------

variable "create_custom_ingress" {
  type        = bool
  description = "Create secondary ingress controller."
  default     = false
}

variable "custom_domain" {
  type        = string
  description = "Custom domain for secondary ingress."
  default     = ""
}

variable "custom_ingress_replicas" {
  type        = number
  description = "Number of ingress controller replicas."
  default     = 2
}

variable "custom_ingress_route_selector" {
  type        = map(string)
  description = "Route label selector for custom ingress."
  default     = {}
}

#------------------------------------------------------------------------------
# GitOps Configuration (Optional)
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
    (projects, quotas, RBAC, apps). When provided, an ArgoCD ApplicationSet
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

variable "oadp_backup_retention_days" {
  type        = number
  description = "Days to retain OADP backups."
  default     = 30
}

variable "monitoring_loki_size" {
  type        = string
  description = <<-EOT
    LokiStack deployment size. Controls resource allocation for Loki components.
    Sizes: 1x.extra-small (dev), 1x.small (prod), 1x.medium (large prod)
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
          secret_name = "apps-wildcard-tls"
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
# Machine Pools Configuration (Optional)
#
# Generic list of machine pools for any workload type.
# Classic supports spot instances for cost optimization.
# See docs/MACHINE-POOLS.md for examples: GPU, bare metal, ARM/Graviton, spot.
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
    spot = optional(object({
      enabled   = bool
      max_price = optional(string)
    }))
    disk_size = optional(number, 300)
    labels    = optional(map(string), {})
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string
    })), [])
    multi_az          = optional(bool, true)
    availability_zone = optional(string)
    subnet_id         = optional(string)
  }))

  description = <<-EOT
    List of additional machine pools to create.
    
    Each pool object supports:
    - name: Pool name (required)
    - instance_type: EC2 instance type (required)
    - replicas: Fixed replica count (default: 2, ignored if autoscaling enabled)
    - autoscaling: { enabled = bool, min = number, max = number }
    - spot: { enabled = bool, max_price = string } (Classic only, up to 90% cost savings)
    - disk_size: Root disk size in GB (default: 300)
    - labels: Map of node labels for workload targeting
    - taints: List of taints for workload isolation
    - multi_az: Distribute across AZs (default: true)
    - availability_zone: Specific AZ (only if multi_az = false)
    - subnet_id: Override default subnet
    
    Examples in docs/MACHINE-POOLS.md:
    - GPU pools (NVIDIA g4dn, p3)
    - GPU Spot pools (cost-effective ML/batch workloads)
    - Bare metal pools (m5.metal for OpenShift Virtualization)
    - ARM/Graviton pools (m6g, m7g for cost optimization)
    - High memory pools (r5, x2idn)
  EOT

  default = []
}

#------------------------------------------------------------------------------
# Proxy Configuration (Optional)
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
  description = "Domains/IPs to exclude from proxy."
  default     = null
}

variable "additional_trust_bundle" {
  type        = string
  description = "Additional CA bundle for proxy (PEM format)."
  default     = null
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
# OIDC Configuration
#
# Three modes are supported for OIDC (operator role authentication):
# 1. Managed (default): Red Hat hosts OIDC, created per-cluster
# 2. Managed (shared): Use pre-created managed OIDC config
# 3. Unmanaged: Customer hosts OIDC in their AWS account
#
# Note: External authentication (external OIDC IdP) is not supported for
# ROSA Classic. Use identity provider configuration post-cluster creation.
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

variable "existing_control_plane_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    (Classic only) List of existing security group IDs to attach to control plane nodes.
    
    Example: ["sg-abc123"]
  EOT
  default     = []
}

variable "existing_infra_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    (Classic only) List of existing security group IDs to attach to infrastructure nodes.
    
    Example: ["sg-abc123"]
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

variable "control_plane_security_group_rules" {
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
    (Classic only) Custom security group rules for control plane nodes.
    
    Example:
    control_plane_security_group_rules = {
      ingress = [
        {
          description = "Allow API access from on-prem"
          from_port   = 6443
          to_port     = 6443
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

variable "infra_security_group_rules" {
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
    (Classic only) Custom security group rules for infrastructure nodes.
    
    Example:
    infra_security_group_rules = {
      ingress = [
        {
          description = "Allow router traffic from corporate LB"
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = ["10.200.0.0/16"]
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
