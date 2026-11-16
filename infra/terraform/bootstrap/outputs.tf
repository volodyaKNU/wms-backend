output "state_bucket" {
  description = "S3 bucket holding the remote state of every WMS Terraform layer."
  value       = aws_s3_bucket.tfstate.bucket
}

output "terraform_ci_user_arn" {
  description = "IAM user used by the Terraform GitHub Actions workflow."
  value       = aws_iam_user.terraform_ci.arn
}

output "terraform_ci_user_name" {
  description = "Name of the Terraform CI IAM user."
  value       = aws_iam_user.terraform_ci.name
}
