#------------------------------------------------------------------------------
# ROSA HCP Account Roles Module - Provider Requirements
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.6.2"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
