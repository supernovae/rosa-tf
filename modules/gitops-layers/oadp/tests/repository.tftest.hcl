mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_partition" { defaults = { partition = "aws", dns_suffix = "amazonaws.com" } }
  mock_data "aws_region" { defaults = { region = "us-east-1" } }
}
mock_provider "random" {}
mock_provider "time" {}
override_resource {
  override_during = plan
  target          = random_id.bucket_suffix
  values          = { hex = "1234abcd" }
}
variables {
  cluster_name      = "oadp-test"
  oidc_endpoint_url = "https://issuer.example.test/cluster/"
}
run "retained_tls_repository" {
  command = plan
  assert {
    condition     = jsondecode(aws_cloudformation_stack.oadp_bucket.template_body).Resources.OADPBucket.DeletionPolicy == "Retain" && jsondecode(aws_cloudformation_stack.oadp_bucket.template_body).Resources.OADPBucket.UpdateReplacePolicy == "Retain"
    error_message = "Backup data must survive stack deletion/replacement."
  }
  assert {
    condition     = length(jsondecode(aws_cloudformation_stack.oadp_bucket.template_body).Resources.OADPBucket.Properties.LifecycleConfiguration.Rules) == 1 && jsondecode(aws_cloudformation_stack.oadp_bucket.template_body).Resources.OADPBucket.Properties.LifecycleConfiguration.Rules[0].Id == "abort-incomplete-uploads"
    error_message = "No object-age expiration of Velero metadata or shared repository chunks."
  }
  assert {
    condition     = jsondecode(aws_cloudformation_stack.oadp_bucket.template_body).Resources.OADPBucketPolicy.Properties.PolicyDocument.Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "Deny non-TLS S3 requests."
  }
  assert {
    condition     = local.oidc_issuer == "issuer.example.test/cluster"
    error_message = "Normalize OIDC issuer consistently for trust conditions and provider ARN."
  }
  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.oadp.statement : alltrue([for a in s.actions : !startswith(a, "ec2:")])])
    error_message = "CSI-only OADP must not have EC2 snapshot permissions."
  }
  assert {
    condition     = anytrue([for c in tolist(data.aws_iam_policy_document.oadp_trust.statement)[0].condition : c.variable == "issuer.example.test/cluster:aud" && contains(c.values, "openshift")])
    error_message = "Require the OADP projected token audience."
  }
}
run "govcloud_kms_repository" {
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
    condition     = startswith(local.bucket_arn, "arn:aws-us-gov:s3:::") && jsondecode(aws_cloudformation_stack.oadp_bucket.template_body).Resources.OADPBucket.Properties.BucketEncryption.ServerSideEncryptionConfiguration[0].ServerSideEncryptionByDefault.SSEAlgorithm == "aws:kms"
    error_message = "Preserve GovCloud partition and customer-managed encryption."
  }
  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.oadp.statement : anytrue([for c in s.condition : c.variable == "kms:ViaService" && contains(c.values, "s3.us-gov-west-1.amazonaws.com")])])
    error_message = "KMS grants must be restricted to regional S3 use."
  }
}
