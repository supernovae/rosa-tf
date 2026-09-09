mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = { cidr_block = "10.1.0.0/24", availability_zone = "us-gov-west-1a" }
  }
  mock_resource "aws_fsx_ontap_storage_virtual_machine" {
    defaults = {
      endpoints = [{
        management = [{ ip_addresses = ["10.1.1.10"] }]
        nfs        = [{ ip_addresses = ["10.1.1.11"] }]
        iscsi      = [{ ip_addresses = ["10.1.1.12"] }]
      }]
    }
  }
}
variables {
  cluster_name       = "storage-test"
  vpc_id             = "vpc-0123456789abcdef0"
  vpc_cidr           = "10.1.0.0/16"
  private_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  fsx_admin_password = "fixture-only-filesystem-9034"
  fsx_svm_password   = "fixture-only-svm-2903"
  kms_key_arn        = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
}
run "bounded_access_and_backups" {
  command = plan
  assert {
    condition     = aws_security_group_rule.fsx_nfs_tcp.cidr_blocks == tolist(["10.1.0.0/24"]) && aws_security_group_rule.fsx_nfs_tcp.from_port == 2049 && aws_security_group_rule.fsx_nfs_tcp.protocol == "tcp"
    error_message = "Use approved worker ranges and NFSv4 TCP, not VPC-wide legacy RPC/UDP access."
  }
  assert {
    condition     = aws_fsx_ontap_file_system.this.automatic_backup_retention_days == 7 && aws_fsx_ontap_file_system.this.kms_key_id == var.kms_key_arn
    error_message = "Preserve native backups and partition-correct KMS encryption."
  }
}
run "multi_az_second_generation" {
  command = plan
  variables {
    deployment_type          = "MULTI_AZ_2"
    throughput_capacity_mbps = 768
    netapp_fsx_config        = { client_route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef1"] }
  }
  assert {
    condition     = aws_fsx_ontap_file_system.this.ha_pairs == 1 && aws_fsx_ontap_file_system.this.throughput_capacity_per_ha_pair == 768 && length(aws_fsx_ontap_file_system.this.route_table_ids) == 2 && length(aws_fsx_ontap_file_system.this.subnet_ids) == 2
    error_message = "Gen2 must use the per-HA-pair field and all Multi-AZ client routes/subnets."
  }
}
run "reject_missing_client_routes" {
  command = plan
  variables { deployment_type = "MULTI_AZ_1" }
  expect_failures = [aws_fsx_ontap_file_system.this]
}
run "reject_invalid_generation_throughput" {
  command = plan
  variables { deployment_type = "SINGLE_AZ_2" }
  expect_failures = [var.throughput_capacity_mbps]
}
run "reject_public_client_range" {
  command = plan
  variables { netapp_fsx_config = { client_cidrs = ["0.0.0.0/0"] } }
  expect_failures = [var.netapp_fsx_config]
}
run "reject_shared_admin_credential" {
  command = plan
  variables { fsx_svm_password = "fixture-only-filesystem-9034" }
  expect_failures = [aws_fsx_ontap_file_system.this]
}
