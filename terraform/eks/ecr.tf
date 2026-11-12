# Private image registry in the same account and region as the cluster.
#
# The nodes pull from it with their own IAM role (AmazonEC2ContainerRegistryReadOnly
# is attached to the node role, and to LabRole in Learner Lab), so no registry
# credentials have to be stored in the cluster.

locals {
  app_images = toset(["todo-backend", "todo-frontend"])
}

resource "aws_ecr_repository" "app" {
  for_each = local.app_images

  name = each.key

  # A tag always means the same image: a deployment can never silently change
  # underneath a running release.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # Lets `terraform destroy` remove the repositories together with their images,
  # so tearing the environment down leaves nothing behind.
  force_delete = true
}

# Keep storage (and cost) bounded: only the 20 most recent images are kept.
resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
