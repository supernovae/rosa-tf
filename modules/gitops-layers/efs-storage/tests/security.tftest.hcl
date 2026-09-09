mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_partition" { defaults = { partition = "aws", dns_suffix = "amazonaws.com" } }
  mock_data "aws_region" { defaults = { region = "us-east-1" } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-012345", availability_zone_id = "use1-az1" } }
}
override_resource {
  target          = aws_efs_file_system.this
  override_during = plan
  values          = { id = "fs-0123456789abcdef0", arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:file-system/fs-0123456789abcdef0" }
}
variables {
  cluster_name       = "efs-test"
  vpc_id             = "vpc-012345"
  private_subnet_ids = ["subnet-012345"]
  oidc_endpoint_url  = "https://issuer.example.test/cluster/"
  efs_config         = { allowed_security_group_ids = ["sg-0123456789abcdef0"] }
}
run "secure_regional_filesystem" {
  command = plan
  assert {
    condition     = aws_efs_file_system.this.encrypted && aws_efs_file_system.this.performance_mode == "generalPurpose" && aws_efs_file_system.this.throughput_mode == "elastic" && aws_efs_backup_policy.this.backup_policy[0].status == "ENABLED"
    error_message = "Require encrypted, performant, automatically backed-up EFS."
  }
  assert {
    condition     = length(aws_security_group.efs.egress) == 0 && alltrue([for rule in aws_security_group.efs.ingress : rule.from_port == 2049 && rule.to_port == 2049 && length(coalesce(rule.cidr_blocks, [])) == 0 && contains(rule.security_groups, "sg-0123456789abcdef0")])
    error_message = "NFS access must be limited to approved worker groups."
  }
  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.efs_csi.statement : s.sid == "EFSCreateAccessPoint" && contains(s.resources, aws_efs_file_system.this.arn)])
    error_message = "Only create access points on this filesystem."
  }
  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.efs_csi.statement : !contains(s.actions, "elasticfilesystem:TagResource") || (length(s.condition) > 0 && !contains(s.resources, "*"))])
    error_message = "Tag mutations must be scoped and conditioned, including post-create reconciliation."
  }
  assert {
    condition     = local.oidc_issuer == "issuer.example.test/cluster" && anytrue([for c in tolist(data.aws_iam_policy_document.efs_csi_trust.statement)[0].condition : c.variable == "issuer.example.test/cluster:aud" && contains(c.values, "openshift")])
    error_message = "Constrain the actual OpenShift projected-token audience."
  }
  assert {
    condition     = alltrue([for sid in ["DenyPlaintext", "DenyRoot", "DenyMountWithoutAccessPoint"] : anytrue([for s in data.aws_iam_policy_document.filesystem.statement : s.sid == sid && s.effect == "Deny"])])
    error_message = "Deny plaintext, root access and mounts without access points."
  }
}
run "govcloud_partition" {
  command = plan
  override_data {
    target = data.aws_partition.current
    values = { partition = "aws-us-gov", dns_suffix = "amazonaws.com" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "us-gov-west-1" }
  }
  variables { kms_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  assert {
    condition     = startswith(local.ap_arn, "arn:aws-us-gov:elasticfilesystem:us-gov-west-1:") && aws_efs_file_system.this.kms_key_id == var.kms_key_arn
    error_message = "Preserve GovCloud partition/region and CMK."
  }
}
run "reject_unencrypted" {
  command = plan
  variables { efs_encrypted = false }
  expect_failures = [aws_efs_file_system.this]
}
run "reject_broad_network_default" {
  command = plan
  variables { efs_config = {} }
  expect_failures = [aws_efs_file_system.this]
}
run "reject_duplicate_az" {
  command = plan
  variables { private_subnet_ids = ["subnet-012345", "subnet-abcdef"] }
  expect_failures = [aws_efs_file_system.this]
}
run "reject_incomplete_provisioned_throughput" {
  command = plan
  variables { efs_throughput_mode = "provisioned" }
  expect_failures = [aws_efs_file_system.this]
}
