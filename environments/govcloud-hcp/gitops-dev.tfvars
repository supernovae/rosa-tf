#------------------------------------------------------------------------------
# ROSA HCP - GovCloud - Dev GitOps Layer Configuration
#
# This file is an OVERLAY applied on top of the cluster tfvars.
# It only contains GitOps-specific settings. All cluster-level variables
# are inherited from cluster-dev.tfvars.
#
# Usage:
#   terraform apply -var-file="cluster-dev.tfvars" -var-file="gitops-dev.tfvars"
#
# NOTE: For private/GovCloud clusters, VPN connectivity is required before
# applying this overlay. See docs/OPERATIONS.md for the deployment workflow.
#------------------------------------------------------------------------------

install_gitops           = true
enable_layer_terminal    = false # Web Terminal operator
enable_layer_oadp        = false # Backup/restore (requires S3 bucket)
enable_layer_monitoring  = false # Prometheus + Loki logging stack
enable_layer_certmanager = false # Cert-Manager with Let's Encrypt (see examples/certmanager.tfvars)
# enable_layer_virtualization = false # Requires bare metal nodes

# Cert-Manager configuration (when enable_layer_certmanager = true)
# certmanager_create_hosted_zone        = true
# certmanager_hosted_zone_domain        = "apps.example.com"
# certmanager_acme_email                = "platform-team@example.com"
# certmanager_enable_dnssec             = true
# certmanager_enable_query_logging      = true
# certmanager_enable_routes_integration = true
# certmanager_certificate_domains = [
#   {
#     name        = "apps-wildcard"
#     namespace   = "openshift-ingress"
#     secret_name = "custom-apps-default-cert"
#     domains     = ["*.apps.example.com"]
#   }
# ]
# # Or use an existing hosted zone:
# # certmanager_hosted_zone_id     = "Z0123456789ABCDEF"
# # certmanager_create_hosted_zone = false

# Monitoring configuration (when enable_layer_monitoring = true)
monitoring_loki_size      = "1x.extra-small" # Dev: extra-small, Prod: 1x.small or larger
monitoring_retention_days = 7                # Dev: 7 days, Prod: 30 days
# monitoring_prometheus_storage_size = "50Gi"  # Default: 100Gi

# Additional GitOps configuration (optional)
# gitops_repo_url = "https://github.com/your-org/my-cluster-config.git"
# gitops_oauth_url = "https://oauth-openshift.apps.<cluster>.<domain>"

# For subsequent runs, uncomment and set from terraform output:
# gitops_cluster_token = "sha256~xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
