terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = ">= 2.4.1, < 3.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.63.0, < 7.0.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "= 1.7.8-prerelease.2"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.14.1, < 1.0.0"
    }
  }
}
