terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1, < 4.0.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.4.1, < 3.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.63.0, < 7.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.3.1, < 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.14.1, < 1.0.0"
    }
  }
}
