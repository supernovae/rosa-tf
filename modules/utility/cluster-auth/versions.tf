terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = ">= 2.4.1, < 3.0.0"
    }
  }
}
