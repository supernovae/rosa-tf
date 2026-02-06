terraform {
  required_version = ">= 1.4.6"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
  }
}
