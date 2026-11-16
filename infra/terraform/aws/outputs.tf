output "region" {
  description = "AWS region of the environment."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate of the EKS API server."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version of the control plane."
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC of the cluster."
  value       = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  description = "Image repository URLs keyed by repository name."
  value       = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}

output "github_deployer_user_name" {
  description = "IAM user used by the application CD jobs."
  value       = aws_iam_user.github_deployer.name
}

output "kubeconfig_command" {
  description = "Configure local kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}
