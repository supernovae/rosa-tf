terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.63.0, < 7.0.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "= 1.7.8-prerelease.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9.0, < 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.14.1, < 1.0.0"
    }
  }
}
