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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1, < 4.0.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.4.1, < 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9.0, < 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.14.1, < 1.0.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.4.1, < 3.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.3.1, < 4.0.0"
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

  # Recommended: Configure backend for state management
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "rosa-hcp/govcloud/terraform.tfstate"
  #   region         = "us-gov-west-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}
