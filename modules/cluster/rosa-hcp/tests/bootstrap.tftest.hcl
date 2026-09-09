# All providers are mocked: these tests never create cloud resources.

mock_provider "rhcs" {
  mock_resource "rhcs_cluster_rosa_hcp" {
    defaults = { current_version = "4.20.0" }
  }
}
mock_provider "time" {}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "TestOnly-Password123!"
    }
  }
}

variables {
  cluster_name         = "provider-test"
  openshift_version    = "4.20.0"
  aws_region           = "us-east-1"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnet_ids   = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
  oidc_config_id       = "test-oidc"
  operator_role_prefix = "test"
  create_admin_user    = true
  admin_username       = "test-admin"
  private_cluster      = true
  aws_account_id       = "123456789012"
  creator_arn          = "arn:aws:iam::123456789012:role/test"
  installer_role_arn   = "arn:aws:iam::123456789012:role/test-Installer"
  support_role_arn     = "arn:aws:iam::123456789012:role/test-Support"
  worker_role_arn      = "arn:aws:iam::123456789012:role/test-Worker"
}
run "commercial_bootstrap" {
  command = apply
  assert {
    condition     = rhcs_cluster_rosa_hcp.this.admin_credentials.username == "test-admin" && output.admin_password == "TestOnly-Password123!"
    error_message = "Native RHCS bootstrap must receive the configured admin and expose the created password."
  }
}
run "creation_only_credentials" {
  command = plan
  variables {
    admin_username = "changed-admin"
  }
  assert {
    condition     = rhcs_cluster_rosa_hcp.this.admin_credentials.username == "test-admin" && output.admin_username == "test-admin"
    error_message = "Changing a creation-only username must preserve the existing credential and reported login."
  }
}
run "native_upgrade_and_autonode_update" {
  command = plan
  variables {
    openshift_version = "4.22.0"
    autonode_role_arn = "arn:aws:iam::123456789012:role/test-Karpenter"
    cluster_options = {
      channel          = "stable-4.22"
      destroy_timeout  = 120
      domain_prefix    = "native-test"
      worker_disk_size = 400
    }
    tags = { CapabilityAudit = "true" }
  }
  assert {
    condition     = rhcs_cluster_rosa_hcp.this.version == "4.22.0" && rhcs_cluster_rosa_hcp.this.auto_node.role_arn == "arn:aws:iam::123456789012:role/test-Karpenter"
    error_message = "Version and AutoNode updates must reach RHCS, not be silently ignored."
  }
  assert {
    condition     = rhcs_cluster_rosa_hcp.this.channel == "stable-4.22" && rhcs_cluster_rosa_hcp.this.destroy_timeout == 120 && rhcs_cluster_rosa_hcp.this.tags["CapabilityAudit"] == "true"
    error_message = "Native channels, timeouts and AWS tags must be wired without channel-group conflicts."
  }
}
run "reject_autonode_before_supported_version" {
  command = plan
  variables { autonode_role_arn = "arn:aws:iam::123456789012:role/test-Karpenter" }
  expect_failures = [rhcs_cluster_rosa_hcp.this]
}
run "reject_autonode_without_create_wait" {
  command = plan
  variables {
    openshift_version        = "4.22.0"
    autonode_role_arn        = "arn:aws:iam::123456789012:role/test-Karpenter"
    wait_for_create_complete = false
  }
  expect_failures = [rhcs_cluster_rosa_hcp.this]
}
run "reject_insecure_registry" {
  command = plan
  variables {
    cluster_options = { registry_config = { registry_sources = { insecure_registries = ["registry.example.com"] } } }
  }
  expect_failures = [var.cluster_options]
}
run "reject_external_auth_bootstrap" {
  command = plan
  variables { external_auth_providers_enabled = true }
  expect_failures = [rhcs_cluster_rosa_hcp.this]
}
run "govcloud_bootstrap" {
  command   = plan
  state_key = "govcloud"
  variables {
    aws_region         = "us-gov-west-1"
    availability_zones = ["us-gov-west-1a", "us-gov-west-1b", "us-gov-west-1c"]
    fips               = true
    is_govcloud        = true
    zero_egress        = true
    creator_arn        = "arn:aws-us-gov:iam::123456789012:role/test"
    installer_role_arn = "arn:aws-us-gov:iam::123456789012:role/test-Installer"
    support_role_arn   = "arn:aws-us-gov:iam::123456789012:role/test-Support"
    worker_role_arn    = "arn:aws-us-gov:iam::123456789012:role/test-Worker"
  }
  assert {
    condition     = rhcs_cluster_rosa_hcp.this.fips && rhcs_cluster_rosa_hcp.this.properties["zero_egress"] == "true" && rhcs_cluster_rosa_hcp.this.admin_credentials.username == "test-admin" && startswith(rhcs_cluster_rosa_hcp.this.sts.role_arn, "arn:aws-us-gov:")
    error_message = "GovCloud bootstrap must retain FIPS, GovCloud IAM ARNs, and native admin creation."
  }
}
run "bootstrap_disabled" {
  command   = plan
  state_key = "disabled"
  variables {
    create_admin_user = false
  }
  assert {
    condition     = length(random_password.cluster_admin) == 0 && output.admin_username == null && output.admin_password == null
    error_message = "Disabling bootstrap on a new cluster must omit credentials and credential outputs."
  }
}
