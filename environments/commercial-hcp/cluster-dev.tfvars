# 2.0 fresh-deployment seed. NOT a ready-to-apply production configuration.
# Copy to a private tfvars file and set openshift_version to a currently offered,
# supported patch for this region/architecture and your selected optional layers.
# RHCS is prerelease: development use also requires allow_prerelease_provider=true.
# See docs/DEPLOYMENT.md. No credentials belong in this file.
cluster_name              = "com-hcp-dev"
environment               = "dev"
aws_region                = "us-east-1"
private_cluster           = true
multi_az                  = true
compute_machine_type      = "m6i.xlarge"
worker_node_count         = 3
cluster_delete_protection = true
cluster_kms_mode          = "create"
infra_kms_mode            = "create"
etcd_encryption           = true
fips                      = false
zero_egress               = false
account_role_prefix       = "ManagedOpenShift"

create_admin_user = true
admin_username    = "bootstrap-admin"
create_jumphost   = false
create_client_vpn = false
install_gitops    = false
machine_pools     = []
tags = {
  Environment = "dev"
  ManagedBy   = "terraform"
}
