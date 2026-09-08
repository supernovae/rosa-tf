# All providers are mocked: these tests never create cloud resources.

run "legacy_seed" {
  command   = apply
  state_key = "legacy"
  module {
    source = "./tests/fixtures/legacy"
  }
  override_resource {
    target = rhcs_cluster_rosa_hcp.this
    values = {
      admin_credentials = { username = "", password = "" }
    }
  }
}
run "legacy_migration" {
  command   = plan
  state_key = "legacy"
  assert {
    condition     = rhcs_cluster_rosa_hcp.this.id == run.legacy_seed.cluster_id && rhcs_cluster_rosa_hcp.this.admin_credentials.username == ""
    error_message = "An existing cluster must keep its identity and must not receive an immutable admin_credentials update."
  }
  assert {
    condition     = output.admin_username == "test-admin" && output.admin_password == "TestOnly-Password123!"
    error_message = "Migration must preserve the previous generated password and login outputs."
  }
}
mock_provider "rhcs" {}
run "unsupported_hcp_autoscaler" {
  command   = plan
  state_key = "unsupported-autoscaler"
  variables {
    cluster_autoscaler_enabled = true
  }
  expect_failures = [var.cluster_autoscaler_enabled]
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
