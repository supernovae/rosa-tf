terraform {
  required_version = ">= 1.4.6"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.6.3"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
