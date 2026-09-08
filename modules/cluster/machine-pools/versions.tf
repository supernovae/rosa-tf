#------------------------------------------------------------------------------
# Machine Pools Module - Provider Requirements
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.7, < 2.0.0"
    }
  }
}
