# The repositories already existed before Terraform; importing keeps their images.
import {
  for_each = var.ecr_repositories
  to       = aws_ecr_repository.app[each.value]
  id       = each.value
}

import {
  for_each = var.ecr_repositories
  to       = aws_ecr_lifecycle_policy.app[each.value]
  id       = each.value
}

resource "aws_ecr_repository" "app" {
  for_each = var.ecr_repositories

  name = each.value

  # CI moves the :latest tag; Deployments always use the immutable commit-SHA tag.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each = var.ecr_repositories

  repository = aws_ecr_repository.app[each.value].name
  policy     = file("${path.module}/ecr-lifecycle-policy.json")
}
