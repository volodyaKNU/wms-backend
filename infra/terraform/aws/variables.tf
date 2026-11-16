variable "region" {
  description = "AWS region of the WMS environment."
  type        = string
  default     = "eu-north-1"
}

variable "environment" {
  description = "Environment name used in tags."
  type        = string
  default     = "lab"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "wms-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the EKS control plane and nodes."
  type        = string
  default     = "1.37"
}

variable "vpc_cidr" {
  description = "CIDR block of the WMS VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "node_instance_type" {
  description = "EC2 instance type of the worker nodes (must be on the lab account's Free Tier allow-list)."
  type        = string
  default     = "c7i-flex.large"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (headroom for rolling node updates)."
  type        = number
  default     = 2
}

variable "app_namespace" {
  description = "Kubernetes namespace the GitHub deployer may modify."
  type        = string
  default     = "wms"
}

variable "ecr_repositories" {
  description = "Application image repositories."
  type        = set(string)
  default     = ["wms-backend", "wms-frontend"]
}

variable "cluster_admin_role_arns" {
  description = "Human IAM roles that get cluster-admin access (the Terraform CI user is added automatically)."
  type        = map(string)
  default = {
    account-full-access = "arn:aws:iam::417392595043:role/managed/AccountFullAccessRole"
  }
}

variable "github_deployer_user_name" {
  description = "IAM user used by the application CD jobs (ECR push + kubectl set image)."
  type        = string
  default     = "wms-github-deployer"
}
