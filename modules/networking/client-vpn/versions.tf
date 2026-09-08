#------------------------------------------------------------------------------
# Client VPN Module - Provider Requirements
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.63.0, < 7.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.4.0, < 5.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.9.0, < 3.0.0"
    }
  }
}
