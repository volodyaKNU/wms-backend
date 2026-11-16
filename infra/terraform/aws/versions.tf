terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  backend "s3" {
    bucket       = "wms-tfstate-417392595043-eu-north-1"
    key          = "aws/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = "wms"
      environment = var.environment
      layer       = "aws"
      managed-by  = "terraform"
    }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket = "wms-tfstate-417392595043-eu-north-1"
    key    = "bootstrap/terraform.tfstate"
    region = "eu-north-1"
  }
}
