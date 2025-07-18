terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.3.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3"
    }
  }
}
