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

output "app_hostname" {
  description = "Public hostname of the application (null = HTTP only); pass as APP_HOSTNAME to scripts/deploy.sh."
  value       = var.app_hostname
}

output "acm_validation_record" {
  description = "DNS record proving ownership of app_hostname: add it at your DNS provider, then wait for the certificate to be issued."
  value = local.acm_validation == null ? null : {
    type  = local.acm_validation.resource_record_type
    name  = local.acm_validation.resource_record_name
    value = local.acm_validation.resource_record_value
  }
}

output "acm_certificate_status" {
  description = "PENDING_VALIDATION until the validation record is found, then ISSUED."
  value       = try(aws_acm_certificate.app[0].status, null)
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
  description = "Variables for the deploy-aws job. AWS_DEPLOY_ENABLED must be a repository variable; the others may live in the aws environment."
  value = merge(
    {
      AWS_DEPLOY_ENABLED = "true"
      AWS_REGION         = var.aws_region
      EKS_CLUSTER_NAME   = aws_eks_cluster.this.name
    },
    var.app_hostname == null ? {} : { APP_HOSTNAME = var.app_hostname },
    # Without a deploy role, the job authenticates with the repository secrets
    # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN instead.
    local.github_deploy_role ? { AWS_ROLE_ARN = local.github_deploy_role_arn } : {},
  )
}
