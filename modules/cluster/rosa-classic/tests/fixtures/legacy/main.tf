# Historical bootstrap shape, used only with mocked providers.
terraform {
  required_version = ">= 1.16.1, < 2.0.0"
  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.7, < 2.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9.0, < 4.0.0"
    }
  }
}
resource "rhcs_cluster_rosa_classic" "this" {
  name               = "provider-test"
  cloud_region       = "us-east-1"
  aws_account_id     = "123456789012"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  aws_subnet_ids     = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
  sts = {
    role_arn             = "arn:aws:iam::123456789012:role/test-Installer"
    support_role_arn     = "arn:aws:iam::123456789012:role/test-Support"
    operator_role_prefix = "test"
    oidc_config_id       = "test-oidc"
    instance_iam_roles = {
      worker_role_arn = "arn:aws:iam::123456789012:role/test-Worker"
      master_role_arn = "arn:aws:iam::123456789012:role/test-ControlPlane"
    }
  }
}
resource "random_password" "admin" {
  count            = 1
  length           = 16
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()_+-="
}
resource "rhcs_identity_provider" "htpasswd" {
  count   = 1
  cluster = rhcs_cluster_rosa_classic.this.id
  name    = "htpasswd"
  htpasswd = {
    users = [{
      username = "test-admin"
      password = random_password.admin[0].result
    }]
  }
}
resource "rhcs_group_membership" "cluster_admin" {
  count   = 1
  cluster = rhcs_cluster_rosa_classic.this.id
  group   = "cluster-admins"
  user    = "test-admin"
}
output "cluster_id" {
  value = rhcs_cluster_rosa_classic.this.id
}
