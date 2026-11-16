terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket       = "wms-tfstate-417392595043-eu-north-1"
    key          = "k8s/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

# Cluster connection details come from the aws layer, so no local kubeconfig
# is needed: the same code runs on a laptop and in GitHub Actions.
data "terraform_remote_state" "aws" {
  backend = "s3"

  config = {
    bucket = "wms-tfstate-417392595043-eu-north-1"
    key    = "aws/terraform.tfstate"
    region = "eu-north-1"
  }
}

locals {
  aws = data.terraform_remote_state.aws.outputs
}

provider "kubernetes" {
  host                   = local.aws.cluster_endpoint
  cluster_ca_certificate = base64decode(local.aws.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.aws.cluster_name, "--region", local.aws.region]
  }
}
