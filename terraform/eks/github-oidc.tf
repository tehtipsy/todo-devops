# Keyless deployments from GitHub Actions.
#
# The workflow exchanges its short-lived OIDC token for temporary AWS
# credentials of the role below. No AWS access key is ever created or stored
# in GitHub, and the trust policy only accepts tokens issued to one repository
# for jobs running in one GitHub environment.
#
# Requires permission to create IAM roles, so it is skipped when
# existing_iam_role_name is set (e.g. Learner Lab); the pipeline then
# authenticates with the sandbox's temporary keys instead.

locals {
  github_oidc_url        = "token.actions.githubusercontent.com"
  github_deploy_role     = !local.use_existing_iam_role
  create_github_oidc     = local.github_deploy_role && var.create_github_oidc_provider
  lookup_github_oidc     = local.github_deploy_role && !var.create_github_oidc_provider
  github_deploy_role_arn = try(aws_iam_role.github_actions_deploy[0].arn, null)
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_github_oidc ? 1 : 0

  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.lookup_github_oidc ? 1 : 0

  url = "https://${local.github_oidc_url}"
}

data "aws_iam_policy_document" "github_actions_trust" {
  count = local.github_deploy_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = [one(concat(
        aws_iam_openid_connect_provider.github[*].arn,
        data.aws_iam_openid_connect_provider.github[*].arn,
      ))]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact match on repository and environment: other repositories, branches
    # and pull requests cannot assume the role.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = ["repo:${var.github_repository}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  count = local.github_deploy_role ? 1 : 0

  name                 = "${local.name}-github-actions-deploy"
  description          = "Assumed by the GitHub Actions deploy job of ${var.github_repository}"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust[0].json
  max_session_duration = 3600
}

# The only AWS API the pipeline needs: reading the cluster's endpoint and CA
# for `aws eks update-kubeconfig`. Everything else is Kubernetes RBAC.
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = local.github_deploy_role ? 1 : 0

  name   = "describe-cluster"
  role   = aws_iam_role.github_actions_deploy[0].id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}

# Maps the role into Kubernetes as the `todo-deployers` group, whose permissions
# are the RBAC bindings in kubernetes.tf. No AWS-managed cluster policy.
resource "aws_eks_access_entry" "github_actions" {
  count = local.github_deploy_role ? 1 : 0

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = aws_iam_role.github_actions_deploy[0].arn
  kubernetes_groups = [local.deployer_group]
  type              = "STANDARD"
}
