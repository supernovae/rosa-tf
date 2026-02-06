# TFLint Configuration
# https://github.com/terraform-linters/tflint

config {
  # Enable all available plugins
  module = true
}

# AWS Plugin
plugin "aws" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Terraform Plugin (built-in rules)
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

#------------------------------------------------------------------------------
# Rule Configuration
#------------------------------------------------------------------------------

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Required providers version
rule "terraform_required_providers" {
  enabled = true
}

# Required version
rule "terraform_required_version" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# Documented variables
rule "terraform_documented_variables" {
  enabled = true
}

# Documented outputs
rule "terraform_documented_outputs" {
  enabled = true
}

#------------------------------------------------------------------------------
# AWS-Specific Rules
#------------------------------------------------------------------------------

# Ensure instance types are valid
rule "aws_instance_invalid_type" {
  enabled = true
}

# Ensure AMI IDs are valid format
rule "aws_instance_invalid_ami" {
  enabled = true
}

# Ensure IAM policies don't use wildcards excessively
rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = false  # Disabled - we handle GovCloud ARNs properly
}
