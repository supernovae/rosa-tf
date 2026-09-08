mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws-us-gov" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}
mock_provider "random" {}
mock_provider "null" {}
mock_provider "time" {}

variables {
  cluster_name      = "test-observe"
  s3_bucket_name    = "test-observe-loki"
  oidc_endpoint_url = "oidc.example.test/cluster"
  aws_region        = "us-gov-west-1"
  kms_key_arn       = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/test"
}

run "retained_encrypted_storage" {
  command = plan
  assert {
    condition     = jsondecode(aws_cloudformation_stack.loki_bucket.template_body).Resources.LokiBucket.DeletionPolicy == "Retain" && jsondecode(aws_cloudformation_stack.loki_bucket.template_body).Resources.LokiBucket.UpdateReplacePolicy == "Retain"
    error_message = "Never destroy or replace the log bucket destructively."
  }
  assert {
    condition     = alltrue([for rule in jsondecode(aws_cloudformation_stack.loki_bucket.template_body).Resources.LokiBucket.Properties.LifecycleConfiguration.Rules : !contains(keys(rule), "ExpirationInDays") && !contains(keys(rule), "ExpirationDate")])
    error_message = "Only Loki may expire current chunks/indexes."
  }
  assert {
    condition     = jsondecode(aws_cloudformation_stack.loki_bucket.template_body).Resources.LokiBucket.Properties.BucketEncryption.ServerSideEncryptionConfiguration[0].ServerSideEncryptionByDefault.KMSMasterKeyID == var.kms_key_arn
    error_message = "Respect customer KMS encryption."
  }
  assert {
    condition     = jsondecode(aws_cloudformation_stack.loki_bucket.template_body).Resources.LokiBucketPolicy.Properties.PolicyDocument.Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "Reject plaintext S3 transport."
  }
  assert {
    condition     = startswith(local.bucket_arn, "arn:aws-us-gov:s3:::")
    error_message = "GovCloud resources must remain in their partition."
  }
  assert {
    condition     = anytrue([for condition in one(data.aws_iam_policy_document.loki_trust.statement).condition : condition.variable == "${var.oidc_endpoint_url}:aud" && contains(condition.values, "sts.amazonaws.com")])
    error_message = "OIDC trust must constrain the token audience."
  }
}
