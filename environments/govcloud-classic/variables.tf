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

variable "ocm_token" {
  type        = string
  description = <<-EOT
    OpenShift Cluster Manager (OCM) offline token for GovCloud.
    Get from: https://console.openshiftusgov.com/openshift/token
    
    Set via environment variable (recommended):
      export TF_VAR_ocm_token="your-offline-token"
    
    IMPORTANT: Do NOT use RHCS_TOKEN or RHCS_URL environment variables.
    They can override provider settings and cause authentication failures.
    If previously set, unset them: unset RHCS_TOKEN RHCS_URL
  EOT
  sensitive   = true

  validation {
    condition     = length(var.ocm_token) > 100
    error_message = "OCM token is required. Get it from https://console.openshiftusgov.com/openshift/token and set via: export TF_VAR_ocm_token=\"your-token\""
  }
}

#------------------------------------------------------------------------------
# AWS Configuration
#------------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS GovCloud region for deployment."
  default     = "us-gov-west-1"

  validation {
    condition     = contains(["us-gov-west-1", "us-gov-east-1"], var.aws_region)
    error_message = "Region must be a valid AWS GovCloud region: us-gov-west-1 or us-gov-east-1."
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
      * 3 private subnets, 3 NAT gateways (or 1 with single_nat_gateway)
      * Minimum 3 worker nodes (1 per AZ)
      * Tolerates single AZ failure
    
    - false: Development/test pattern with single AZ
      * 1 private subnet, 1 NAT gateway
      * Minimum 2 worker nodes
      * Lower cost (~66% less NAT charges)
      * Same security posture (FIPS, encryption, private cluster)
    
    NOTE: Changing from single-AZ to multi-AZ requires cluster recreation.
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
    error_message = "Must specify 1 AZ (single-AZ) or 3 AZs (multi-AZ), or leave null for auto-selection."
  }
}

#------------------------------------------------------------------------------
# OpenShift Configuration
#------------------------------------------------------------------------------

variable "openshift_version" {
  type        = string
  description = <<-EOT
    OpenShift version for the cluster (x.y.z format).
    
    To see available versions, run:
      rosa list versions --channel-group eus
      rosa list versions --channel-group stable
    
    Example output:
      VERSION         DEFAULT  AVAILABLE UPGRADES
      4.16.50         no
      4.16.49         no       4.16.50
      4.16.48         no       4.16.49, 4.16.50
  EOT
  default     = "4.16.50"

  validation {
    condition     = can(regex("^4\\.[0-9]+\\.[0-9]+$", var.openshift_version))
    error_message = "OpenShift version must be in x.y.z format (e.g., 4.16.50). Run 'rosa list versions' to see available versions."
  }
}

variable "channel_group" {
  type        = string
  description = <<-EOT
    Update channel group for the cluster. Only two options are supported:

    - "eus" (default): Extended Update Support - Recommended for GovCloud/FedRAMP.
      Provides extended lifecycle support for even-numbered releases (4.14, 4.16, etc).
      EUS releases receive security patches and critical fixes for up to 24 months.

    - "stable": Standard support channel for all releases.
      Use this when upgrading to odd-numbered releases (4.15, 4.17, etc) or when
      you want access to the latest features without EUS lifecycle.

    LIFECYCLE GUIDANCE:
    - Start with channel_group = "eus" and openshift_version = "4.16"
    - When ready to upgrade beyond EUS, change to channel_group = "stable"
    - After upgrading to the next EUS version (e.g., 4.18), switch back to "eus"

    See: https://access.redhat.com/support/policy/updates/openshift-eus
  EOT
  default     = "eus"

  validation {
    condition     = contains(["eus", "stable"], var.channel_group)
    error_message = "Channel group must be 'eus' or 'stable'. Use 'eus' for extended lifecycle support on even-numbered releases."
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
# VPC Configuration
#------------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets (one per AZ). If null, will be auto-calculated."
  default     = null
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (one per AZ). Only used when egress_type = 'nat'. If null, will be auto-calculated."
  default     = null
}

variable "egress_type" {
  type        = string
  description = <<-EOT
    Type of internet egress for the private subnets:
    - "nat": Creates public subnets, Internet Gateway, and NAT gateways (standalone deployment)
    - "tgw": No public infrastructure; egress via Transit Gateway (requires transit_gateway_id)
    - "proxy": No public infrastructure; egress via HTTP/HTTPS proxy configured in cluster
  EOT
  default     = "nat"

  validation {
    condition     = contains(["nat", "tgw", "proxy"], var.egress_type)
    error_message = "egress_type must be one of: nat, tgw, proxy"
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit Gateway ID for egress routing. Required when egress_type = 'tgw'."
  default     = null
}

variable "transit_gateway_route_cidr" {
  type        = string
  description = "CIDR block to route via Transit Gateway (typically 0.0.0.0/0 for internet egress)."
  default     = "0.0.0.0/0"
}

variable "enable_vpc_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs. Logs are encrypted with the infrastructure KMS key and sent to CloudWatch."
  default     = false
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Number of days to retain VPC flow logs in CloudWatch."
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
  description = <<-EOT
    Number of worker nodes.
    - Multi-AZ: Minimum 3 (1 per AZ for HA)
    - Single-AZ: Minimum 2 (for pod scheduling flexibility)
    
    Default is 3 for production deployments.
  EOT
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

  validation {
    condition     = var.worker_disk_size >= 128
    error_message = "Worker disk size must be at least 128 GB."
  }
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
  description = "CIDR block for pod IPs."
  default     = "10.128.0.0/14"
}

variable "service_cidr" {
  type        = string
  description = "CIDR block for service IPs."
  default     = "172.30.0.0/16"
}

variable "host_prefix" {
  type        = number
  description = "Subnet prefix length for each node."
  default     = 23

  validation {
    condition     = var.host_prefix >= 23 && var.host_prefix <= 26
    error_message = "Host prefix must be between 23 and 26."
  }
}

variable "etcd_encryption" {
  type        = bool
  description = "Enable etcd encryption on top of storage encryption."
  default     = true
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

variable "disable_workload_monitoring" {
  type        = bool
  description = "Disable user workload monitoring."
  default     = false
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

variable "permissions_boundary" {
  type        = string
  description = "ARN of IAM policy to use as permissions boundary for created roles."
  default     = ""
}

variable "path" {
  type        = string
  description = "IAM path for roles and policies."
  default     = "/"
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
# Jump Host Configuration
#------------------------------------------------------------------------------

variable "create_jumphost" {
  type        = bool
  description = "Create an SSM-enabled jump host for cluster access."
  default     = true
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
# Client VPN Configuration (Optional)
#------------------------------------------------------------------------------
# AWS Client VPN provides direct network connectivity to the VPC as an
# alternative to SSM port forwarding. Benefits include:
# - Native DNS resolution for cluster endpoints
# - No certificate warnings (proper TLS works)
# - No port forwarding management
# See modules/client-vpn/README.md for cost analysis and usage details.
#------------------------------------------------------------------------------

variable "create_client_vpn" {
  type        = bool
  description = <<-EOT
    Create an AWS Client VPN endpoint for direct VPC access.
    This is an alternative to SSM-based access with benefits like
    native DNS resolution and no port forwarding required.
    See modules/client-vpn/README.md for cost analysis.
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
# Custom Ingress Configuration (Optional)
#------------------------------------------------------------------------------

variable "create_custom_ingress" {
  type        = bool
  description = "Create a secondary ingress controller for custom domain."
  default     = false
}

variable "custom_domain" {
  type        = string
  description = "Custom domain for secondary ingress (e.g., apps.mydomain.com)."
  default     = ""
}

variable "custom_ingress_replicas" {
  type        = number
  description = "Number of replicas for custom ingress controller."
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
    - Older OpenShift version with different OAuth routing (e.g., 4.16)
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
    
    To obtain: oc login <cluster> && oc whoami -t
  EOT
  default     = null
  sensitive   = true
}

#------------------------------------------------------------------------------
# GitOps Layer Enablement
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
    Creates S3 bucket and IAM role, then deploys OADP operator via GitOps.
    Provides cluster backup and restore capabilities using Velero.
  EOT
  default     = false
}

variable "oadp_backup_retention_days" {
  type        = number
  description = "Number of days to retain OADP backups in S3."
  default     = 30
}

variable "enable_layer_virtualization" {
  type        = bool
  description = <<-EOT
    Enable the OpenShift Virtualization layer.
    Creates a bare metal machine pool, then deploys OpenShift Virtualization via GitOps.
    Provides VM capabilities on OpenShift using KubeVirt.
  EOT
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
# Note: Check GovCloud availability for specific instance types.
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
    - spot: { enabled = bool, max_price = string } (up to 90% cost savings)
    - disk_size: Root disk size in GB (default: 300)
    - labels: Map of node labels for workload targeting
    - taints: List of taints for workload isolation
    - multi_az: Distribute across AZs (default: true)
    - availability_zone: Specific AZ (only if multi_az = false)
    - subnet_id: Override default subnet
    
    GovCloud GPU instances: p3.2xlarge, p3.8xlarge, g4dn.xlarge (check availability)
    
    Examples in docs/MACHINE-POOLS.md:
    - GPU pools (NVIDIA)
    - GPU Spot pools (cost-effective ML/batch workloads)
    - Bare metal pools (m5.metal for OpenShift Virtualization)
    - ARM/Graviton pools (check GovCloud availability)
    - High memory pools (r5, x2idn)
  EOT

  default = []
}

#------------------------------------------------------------------------------
# Cluster Egress Proxy Configuration (Optional)
#------------------------------------------------------------------------------

variable "http_proxy" {
  type        = string
  description = "HTTP proxy URL for cluster egress."
  default     = null
}

variable "https_proxy" {
  type        = string
  description = "HTTPS proxy URL for cluster egress."
  default     = null
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated list of domains/IPs to exclude from proxy."
  default     = null
}

variable "additional_trust_bundle" {
  type        = string
  description = "PEM-encoded X.509 certificate bundle for proxy CA."
  default     = null
}

#------------------------------------------------------------------------------
# KMS Encryption Configuration
# Note: Customer-managed KMS is MANDATORY for GovCloud (FedRAMP compliance)
#
# Two separate keys with independent modes for blast radius containment:
# - cluster_kms_*: For ROSA workers and etcd ONLY
# - infra_kms_*: For jump host, CloudWatch, S3/OADP, VPN ONLY
#
# NOTE: "provider_managed" is NOT available by default in GovCloud.
# FedRAMP SC-12/SC-13 requires customer control over cryptographic keys.
#
# ADVANCED: For dev/staging, you CAN use "existing" mode with the AWS managed
# aws/ebs key ARN at your own risk. This is NOT recommended for production.
#------------------------------------------------------------------------------

variable "cluster_kms_mode" {
  type        = string
  description = <<-EOT
    Cluster KMS key management mode (FedRAMP requires customer-managed keys):
    
    - "create" (DEFAULT): Terraform creates customer-managed KMS key
    - "existing": Use an existing KMS key ARN (set cluster_kms_key_arn)
    
    This key is used ONLY for ROSA-managed resources (workers, etcd).
  EOT
  default     = "create"

  validation {
    condition     = contains(["create", "existing"], var.cluster_kms_mode)
    error_message = "GovCloud requires customer-managed KMS. cluster_kms_mode must be 'create' or 'existing'."
  }
}

variable "cluster_kms_key_arn" {
  type        = string
  description = "ARN of existing KMS key for cluster. Required when cluster_kms_mode = 'existing'."
  default     = null

  validation {
    condition     = var.cluster_kms_key_arn == null || can(regex("^arn:aws-us-gov:kms:", var.cluster_kms_key_arn))
    error_message = "cluster_kms_key_arn must be a valid GovCloud KMS key ARN."
  }
}

variable "infra_kms_mode" {
  type        = string
  description = <<-EOT
    Infrastructure KMS key management mode (FedRAMP requires customer-managed keys):
    
    - "create" (DEFAULT): Terraform creates customer-managed KMS key
    - "existing": Use an existing KMS key ARN (set infra_kms_key_arn)
    
    This key is used ONLY for non-ROSA resources:
    - Jump host EBS volumes
    - CloudWatch log encryption
    - S3 bucket encryption (OADP, backups)
    - VPN connection logs
    
    IMPORTANT: Separate from cluster KMS for blast radius containment.
  EOT
  default     = "create"

  validation {
    condition     = contains(["create", "existing"], var.infra_kms_mode)
    error_message = "GovCloud requires customer-managed KMS. infra_kms_mode must be 'create' or 'existing'."
  }
}

variable "infra_kms_key_arn" {
  type        = string
  description = "ARN of existing KMS key for infrastructure. Required when infra_kms_mode = 'existing'."
  default     = null

  validation {
    condition     = var.infra_kms_key_arn == null || can(regex("^arn:aws-us-gov:kms:", var.infra_kms_key_arn))
    error_message = "infra_kms_key_arn must be a valid GovCloud KMS key ARN."
  }
}

variable "kms_key_deletion_window" {
  type        = number
  description = "Days before KMS keys are deleted (7-30). Only applies when creating keys."
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
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
