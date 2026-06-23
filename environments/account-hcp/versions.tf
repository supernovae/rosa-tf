#------------------------------------------------------------------------------
# ROSA HCP Account Layer - Provider Requirements
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.7"
    }
  }
}
