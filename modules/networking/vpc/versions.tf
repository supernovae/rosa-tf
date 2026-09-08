terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.63.0, < 7.0.0"
    }
  }
}
