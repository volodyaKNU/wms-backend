terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # The bucket below is created by this very configuration. The first apply
  # runs with local state, then `terraform init -migrate-state` moves it here.
  backend "s3" {
    bucket       = "wms-tfstate-417392595043-eu-north-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "wms"
      layer      = "bootstrap"
      managed-by = "terraform"
    }
  }
}
