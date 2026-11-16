variable "region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "eu-north-1"
}

variable "terraform_ci_user_name" {
  description = "IAM user used by GitHub Actions to run terraform plan/apply."
  type        = string
  default     = "wms-terraform-ci"
}
