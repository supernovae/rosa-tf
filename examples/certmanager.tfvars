#------------------------------------------------------------------------------
# ROSA HCP - Cert-Manager with Let's Encrypt DNS01
#
# Complete development cluster with automated TLS certificate management.
# cert-manager handles certificate lifecycle using Let's Encrypt with
# DNS01 challenges via Route53 (IRSA-based, no static credentials).
#
# This example creates:
#   - Private HCP cluster with public access disabled
#   - cert-manager operator with Let's Encrypt ClusterIssuers (prod + staging)
#   - Route53 hosted zone for DNS01 challenges
#   - Wildcard certificate for the apps domain
#   - OpenShift Routes integration for auto-TLS on annotated Routes
#
# NOTE: cert-manager requires outbound internet access for ACME challenges.
#       It CANNOT be used on zero-egress clusters.
#       For air-gapped environments, provide certificates manually.
#
# Usage:
#   cp examples/certmanager.tfvars environments/commercial-hcp/certmanager-dev.tfvars
#   # Edit cluster_name, aws_region, certmanager_* values
#   cd environments/commercial-hcp
#   terraform init
#   terraform plan -var-file="certmanager-dev.tfvars"
#   terraform apply -var-file="certmanager-dev.tfvars"
#
# After deployment:
#   1. If zone was created, delegate DNS from registrar to AWS nameservers
#      (shown in terraform output)
#   2. ClusterIssuer "letsencrypt-production" is ready
#   3. Annotate Routes for auto-TLS:
#      oc annotate route <name> \
#        cert-manager.io/issuer-kind=ClusterIssuer \
#        cert-manager.io/issuer-name=letsencrypt-production
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification
#------------------------------------------------------------------------------

cluster_name = "certmgr-dev"
environment  = "dev"
aws_region   = "us-east-1"

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.20.10"
channel_group     = "stable"

#------------------------------------------------------------------------------
# Network Configuration
# Single-AZ for cost savings in dev
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = false

#------------------------------------------------------------------------------
# Cluster Configuration
# Private cluster - cert-manager works on both public and private clusters
# since DNS01 challenge only needs outbound HTTPS (not inbound)
#------------------------------------------------------------------------------

private_cluster      = true
compute_machine_type = "m5.xlarge"
worker_node_count    = 2

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

cluster_kms_mode = "provider_managed"
infra_kms_mode   = "provider_managed"
etcd_encryption  = false

#------------------------------------------------------------------------------
# Zero Egress - MUST be false for cert-manager
# DNS01 challenge requires outbound HTTPS to Let's Encrypt ACME servers
#------------------------------------------------------------------------------

zero_egress = false

#------------------------------------------------------------------------------
# ECR / OIDC / IAM
#------------------------------------------------------------------------------

create_ecr          = false
create_oidc_config  = true
managed_oidc        = true
account_role_prefix = "ManagedOpenShift"

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# External Authentication (HCP Only)
#------------------------------------------------------------------------------

external_auth_providers_enabled = false

#------------------------------------------------------------------------------
# Machine Pools
#------------------------------------------------------------------------------

machine_pools = []

#------------------------------------------------------------------------------
# Access Configuration
#------------------------------------------------------------------------------

create_jumphost   = false
create_client_vpn = false

#------------------------------------------------------------------------------
# GitOps Configuration
# Only enable cert-manager layer - other layers left off for clarity
#------------------------------------------------------------------------------

install_gitops = true

# Layer enablement
enable_layer_terminal       = true # Web terminal (lightweight, no infra)
enable_layer_oadp           = false
enable_layer_virtualization = false
enable_layer_monitoring     = false
enable_layer_certmanager    = true # <-- Cert-Manager with Let's Encrypt

#------------------------------------------------------------------------------
# Cert-Manager Configuration
#
# How it works:
#   1. Terraform creates an IAM role with Route53 permissions (IRSA)
#   2. cert-manager operator is installed from OperatorHub
#   3. ServiceAccount is annotated with the IAM role ARN
#   4. ClusterIssuer is created pointing to Let's Encrypt + Route53
#   5. Certificate resources are created for your domains
#   6. cert-manager auto-renews certificates 30 days before expiry
#------------------------------------------------------------------------------

# --- Option A: Use an existing Route53 hosted zone ---
# certmanager_hosted_zone_id     = "Z0123456789ABCDEF"
# certmanager_create_hosted_zone = false

# --- Option B: Create a new Route53 hosted zone ---
# NOTE: You must delegate DNS from your registrar to the AWS nameservers
# shown in terraform output after the first apply.
certmanager_create_hosted_zone = true
certmanager_hosted_zone_domain = "apps.example.com"

# DNSSEC signing (default: true) - protects against DNS spoofing
# After first apply, add the DS record from outputs to your domain registrar
# to complete the chain of trust. Set to false to disable.
certmanager_enable_dnssec = true

# DNS query logging (default: true) - logs queries to CloudWatch
# NOTE: For Commercial AWS, requires deployment in us-east-1.
# Set to false for non-us-east-1 commercial deployments.
certmanager_enable_query_logging = true

# Let's Encrypt registration email (receives expiry warnings)
certmanager_acme_email = "platform-team@example.com"

# Pre-create Certificate resources (optional)
# cert-manager handles renewal automatically (30 days before 90-day expiry)
certmanager_certificate_domains = [
  {
    name        = "apps-wildcard"
    namespace   = "openshift-ingress"
    secret_name = "apps-wildcard-tls"
    domains     = ["*.apps.example.com"]
  }
]

# Enable OpenShift Routes integration (default: true)
# Allows annotating Routes for automatic TLS provisioning
certmanager_enable_routes_integration = true

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "dev"
  CostCenter  = "development"
  Layers      = "certmanager"
}
