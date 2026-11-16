################################################################################
# IAM user for the application CD jobs (wms-backend / wms-frontend workflows)
#
# It was created by hand before Terraform existed, therefore it is imported.
# Its access key is managed outside Terraform so the secret never lands in the
# state file; it lives only in GitHub Actions secrets.
################################################################################

import {
  to = aws_iam_user.github_deployer
  id = "wms-github-deployer"
}

import {
  to = aws_iam_user_policy.github_deployer
  id = "wms-github-deployer:wms-github-cd"
}

resource "aws_iam_user" "github_deployer" {
  name = var.github_deployer_user_name
}

data "aws_iam_policy_document" "github_deployer" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushWmsImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = [for repo in aws_ecr_repository.app : repo.arn]
  }

  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_user_policy" "github_deployer" {
  name   = "wms-github-cd"
  user   = aws_iam_user.github_deployer.name
  policy = data.aws_iam_policy_document.github_deployer.json
}
