output "region" {
  description = "AWS region of the cluster."
  value       = var.aws_region
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "ecr_registry" {
  description = "Registry host of the ECR repositories; use as IMAGE_REGISTRY for scripts/deploy.sh."
  value       = split("/", aws_ecr_repository.app["todo-backend"].repository_url)[0]
}

output "configure_kubectl" {
  description = "Command that points kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "github_actions_role_arn" {
  description = "Role assumed by the deploy-aws job through GitHub OIDC (null when existing_iam_role_name is set)."
  value       = local.github_deploy_role_arn
}

output "github_actions_variables" {
  description = "Repository variables to set in the DevOps repository to enable the deploy-aws job."
  value = merge(
    {
      AWS_DEPLOY_ENABLED = "true"
      AWS_REGION         = var.aws_region
      EKS_CLUSTER_NAME   = aws_eks_cluster.this.name
    },
    # Without a deploy role, the job authenticates with the repository secrets
    # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN instead.
    local.github_deploy_role ? { AWS_ROLE_ARN = local.github_deploy_role_arn } : {},
  )
}
