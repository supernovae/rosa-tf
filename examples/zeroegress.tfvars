#------------------------------------------------------------------------------
# ROSA HCP - Zero Egress Example
#
# Complete example for a zero-egress (air-gapped) cluster with no internet access.
# The cluster pulls OpenShift images from Red Hat's regional ECR and custom
# operators from your own ECR repository.
#
# COPY this file to your environment and customize cluster_name, region, etc.
#
# What's different from dev.tfvars:
#   - zero_egress = true (no NAT gateway, no internet)
#   - ECR repository created for operator mirroring
#   - VPN enabled for cluster access
#   - IDMS config generated for registry mirroring
#   - No GitOps layers (would require mirrored operators)
#
# Usage:
#   cp examples/zeroegress.tfvars environments/commercial-hcp/my-cluster.tfvars
#   cd environments/commercial-hcp
#   # Edit my-cluster.tfvars with your cluster_name, region, etc.
#   terraform apply -var-file="my-cluster.tfvars"
#
# After Deployment - See "Next Steps" section at bottom of this file.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Cluster Identification - CUSTOMIZE THESE
#------------------------------------------------------------------------------

cluster_name = "dev-zeroegress" # <-- CHANGE THIS
environment  = "dev"
aws_region   = "us-east-1" # <-- CHANGE THIS

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------

openshift_version = "4.20.10" # <-- Zero egress requires 4.18+
channel_group     = "stable"

#------------------------------------------------------------------------------
# Network Configuration
#
# Zero egress creates a minimal VPC with private subnets only.
# No NAT gateway, no internet gateway - fully air-gapped.
#------------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"
multi_az = false # Set true for production HA

#------------------------------------------------------------------------------
# Zero Egress Configuration
#
# This is the key setting - enables air-gapped operation.
# Automatically sets egress_type="none" (no NAT/IGW).
#------------------------------------------------------------------------------

zero_egress     = true # <-- Enables air-gapped mode
private_cluster = true # <-- Required for zero egress

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

compute_machine_type = "m5.xlarge"
worker_node_count    = 3

#------------------------------------------------------------------------------
# Encryption Configuration
#------------------------------------------------------------------------------

cluster_kms_mode = "provider_managed"
infra_kms_mode   = "provider_managed"

#------------------------------------------------------------------------------
# IAM Configuration (HCP requires account roles to exist first)
#------------------------------------------------------------------------------

account_role_prefix = "ManagedOpenShift"

#------------------------------------------------------------------------------
# OIDC Configuration
#------------------------------------------------------------------------------

create_oidc_config = true
managed_oidc       = true

#------------------------------------------------------------------------------
# External Authentication (HCP Only)
#------------------------------------------------------------------------------

external_auth_providers_enabled = false

#------------------------------------------------------------------------------
# Admin User
#------------------------------------------------------------------------------

create_admin_user = true
admin_username    = "cluster-admin"

#------------------------------------------------------------------------------
# Machine Pools
#------------------------------------------------------------------------------

machine_pools = []

#------------------------------------------------------------------------------
# Access Configuration
#
# VPN is essential for zero egress - no other way to reach the cluster.
# SSM provides backup access for debugging node issues.
#------------------------------------------------------------------------------

create_jumphost   = false
create_client_vpn = true # <-- Required for cluster access

#------------------------------------------------------------------------------
# ECR Configuration
#
# Creates a private ECR repository for operator mirroring.
# The IDMS config is automatically generated to redirect image pulls.
#------------------------------------------------------------------------------

create_ecr               = true # <-- Creates ECR for operator mirroring
ecr_repository_name      = ""   # <-- Defaults to {cluster_name}-registry
ecr_prevent_destroy      = true # <-- Protect mirrored images from destroy
ecr_create_vpc_endpoints = true # <-- Required for private ECR access

#------------------------------------------------------------------------------
# GitOps Configuration
#
# GitOps is DISABLED for zero egress clusters because:
# - GitOps operators must be mirrored to ECR first
# - IDMS must be applied before installing operators
# - See "Next Steps" below for enabling GitOps after mirroring
#------------------------------------------------------------------------------

install_gitops              = false # <-- Disabled until operators mirrored
enable_layer_terminal       = false
enable_layer_oadp           = false
enable_layer_virtualization = false
enable_layer_monitoring     = false

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

enable_timing = true

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

tags = {
  Environment = "dev"
  Purpose     = "zeroegress-example"
  NetworkMode = "air-gapped"
}

#------------------------------------------------------------------------------
# NEXT STEPS - After Terraform Apply
#------------------------------------------------------------------------------
#
# 1. CONNECT TO CLUSTER (via VPN)
#    - Download OpenVPN config from terraform output
#    - Connect: openvpn --config outputs/vpn-config.ovpn
#    - Login: oc login $(terraform output -raw api_url) -u cluster-admin
#
# 2. APPLY IDMS CONFIGURATION
#    - This tells OpenShift to pull from your ECR instead of public registries
#    - File is generated at: outputs/idms-config.yaml
#    
#    oc apply -f outputs/idms-config.yaml
#
# 3. MIRROR OPERATORS TO ECR
#    - From a machine WITH internet access, mirror needed operators:
#    
#    # Generate mirror config (includes all GitOps layer operators)
#    ./scripts/mirror-operators.sh layers \
#      --ocp-version 4.17 \
#      --ecr-url $(terraform output -raw ecr_registry_url)
#    
#    # Mirror to local disk
#    oc-mirror --config ./mirror-workspace/imageset-config-layers.yaml \
#      file://./mirror-data
#    
#    # Transfer mirror-data to air-gapped network, then push to ECR:
#    ECR_URL=$(terraform output -raw ecr_registry_url)
#    aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_URL
#    oc-mirror --from ./mirror-data docker://$ECR_URL
#
# 4. ENABLE GITOPS (Optional - after mirroring)
#    - Update tfvars: install_gitops = true
#    - Re-run: terraform apply -var-file="my-cluster.tfvars"
#    - GitOps operators will now pull from your ECR
#
# For detailed instructions, see: docs/ZERO-EGRESS.md
#------------------------------------------------------------------------------
