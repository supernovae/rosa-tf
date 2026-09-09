# All providers are mocked: these tests never create cloud resources.

mock_provider "rhcs" {}
mock_provider "time" {}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "TestOnly-Password123!"
    }
  }
}
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/test"
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}
mock_provider "aws" {
  alias = "gov"
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws-us-gov:iam::123456789012:role/test"
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws-us-gov" }
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
  machine_cidr         = "10.0.0.0/16"
  account_role_prefix  = "test"
}
run "commercial_bootstrap" {
  command = apply
  assert {
    condition     = rhcs_cluster_rosa_classic.this.admin_credentials.username == "test-admin" && output.admin_password == "TestOnly-Password123!"
    error_message = "Native RHCS bootstrap must receive the configured admin and expose the created password."
  }
}
run "creation_only_credentials" {
  command = plan
  variables {
    admin_username = "changed-admin"
  }
  assert {
    condition     = rhcs_cluster_rosa_classic.this.admin_credentials.username == "test-admin" && output.admin_username == "test-admin"
    error_message = "Changing a creation-only username must preserve the existing credential and reported login."
  }
}
run "native_upgrade_and_tags" {
  command = plan
  variables {
    openshift_version = "4.22.0"
    cluster_options   = { channel = "stable-4.22", destroy_timeout = 120 }
    tags              = { CapabilityAudit = "true" }
  }
  assert {
    condition     = rhcs_cluster_rosa_classic.this.version == "4.22.0" && rhcs_cluster_rosa_classic.this.channel == "stable-4.22" && rhcs_cluster_rosa_classic.this.tags["CapabilityAudit"] == "true"
    error_message = "Classic upgrades, native channels and AWS tags must reach RHCS."
  }
}
run "trust_bundle_without_forward_proxy" {
  command = plan
  variables { additional_trust_bundle = "test-only-ca-bundle" }
  assert {
    condition     = rhcs_cluster_rosa_classic.this.proxy.additional_trust_bundle == "test-only-ca-bundle"
    error_message = "A standalone trusted CA bundle must not be silently discarded."
  }
}
run "govcloud_bootstrap" {
  command   = plan
  state_key = "govcloud"
  providers = {
    aws    = aws.gov
    rhcs   = rhcs
    random = random
    time   = time
  }
  variables {
    aws_region         = "us-gov-west-1"
    availability_zones = ["us-gov-west-1a", "us-gov-west-1b", "us-gov-west-1c"]
    fips               = true
  }
  assert {
    condition     = rhcs_cluster_rosa_classic.this.fips && rhcs_cluster_rosa_classic.this.admin_credentials.username == "test-admin" && startswith(rhcs_cluster_rosa_classic.this.sts.role_arn, "arn:aws-us-gov:")
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
    condition     = length(random_password.admin) == 0 && output.admin_username == null && output.admin_password == null
    error_message = "Disabling bootstrap on a new cluster must omit credentials and credential outputs."
  }
}
