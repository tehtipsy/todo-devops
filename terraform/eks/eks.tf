# The EKS cluster, its worker nodes and core add-ons, written as plain
# resources. (The terraform-aws-modules/eks module always looks up the caller's
# IAM role with iam:GetRole, which sandbox accounts such as AWS Academy Learner
# Lab explicitly deny - so it cannot be used there.)

data "aws_partition" "current" {}

locals {
  # Sandboxes that forbid creating IAM roles (e.g. Learner Lab's LabRole) reuse
  # one existing role for the cluster, the nodes and the in-cluster controllers.
  use_existing_iam_role = var.existing_iam_role_name != null

  cluster_role_arn = local.use_existing_iam_role ? data.aws_iam_role.existing[0].arn : aws_iam_role.cluster[0].arn
  node_role_arn    = local.use_existing_iam_role ? data.aws_iam_role.existing[0].arn : aws_iam_role.node[0].arn

  # With dedicated roles, controllers get credentials through EKS Pod Identity
  # and pods are blocked from the node's metadata service (hop limit 1). With a
  # shared existing role, controllers have to borrow the node's credentials,
  # which requires a second network hop.
  node_metadata_hop_limit = local.use_existing_iam_role ? 2 : 1

  aws_managed_policy = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}

data "aws_iam_role" "existing" {
  count = local.use_existing_iam_role ? 1 : 0

  name = var.existing_iam_role_name
}

# --- IAM roles (only when the account allows creating them) -------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count = local.use_existing_iam_role ? 0 : 1

  name               = "${local.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = local.use_existing_iam_role ? 0 : 1

  role       = aws_iam_role.cluster[0].name
  policy_arn = "${local.aws_managed_policy}/AmazonEKSClusterPolicy"
}

# The control plane needs the secrets-encryption key, and only that key.
data "aws_iam_policy_document" "cluster_kms" {
  statement {
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey", "kms:CreateGrant", "kms:ListGrants"]
    resources = [aws_kms_key.eks.arn]
  }
}

resource "aws_iam_role_policy" "cluster_kms" {
  count = local.use_existing_iam_role ? 0 : 1

  name   = "secrets-encryption-key"
  role   = aws_iam_role.cluster[0].id
  policy = data.aws_iam_policy_document.cluster_kms.json
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.use_existing_iam_role ? 0 : 1

  name               = "${local.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.use_existing_iam_role ? toset([]) : toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node[0].name
  policy_arn = "${local.aws_managed_policy}/${each.key}"
}

# --- Control plane -----------------------------------------------------------

# Envelope encryption of Kubernetes Secrets. The default key policy delegates
# access to IAM, so only principals granted kms:Decrypt on this key can use it.
resource "aws_kms_key" "eks" {
  description             = "Encrypts Kubernetes Secrets in ${local.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.cluster_name}"
  target_key_id = aws_kms_key.eks.key_id
}

# Created up front so the retention period applies; EKS would otherwise create
# the group itself with logs kept forever.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = local.cluster_role_arn

  # Control-plane audit and authenticator logs go to CloudWatch.
  enabled_cluster_log_types = ["audit", "authenticator"]

  # Core add-ons are installed below as managed add-ons, with versions and
  # configuration under Terraform's control.
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids = module.vpc.private_subnets
    # Reachable from the internet (so GitHub-hosted runners can deploy) and
    # from inside the VPC (so nodes do not hairpin through the NAT gateway).
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  access_config {
    # Access is managed with EKS access entries only (no aws-auth ConfigMap).
    authentication_mode = "API"
    # Whoever runs `terraform apply` becomes cluster admin.
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  # Avoid the surcharge for extended support: upgrade before standard support ends.
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.eks,
  ]
}

# --- Add-ons -----------------------------------------------------------------

locals {
  # Needed before nodes can become Ready: pod networking (with NetworkPolicy
  # enforcement for the application's policies), Service routing, and the agent
  # that hands out Pod Identity credentials.
  before_compute_addons = merge(
    {
      "vpc-cni"    = jsonencode({ enableNetworkPolicy = "true" })
      "kube-proxy" = null
    },
    local.use_existing_iam_role ? {} : { "eks-pod-identity-agent" = null },
  )

  # Deployments: these need running nodes to become healthy.
  after_compute_addons = {
    "coredns" = null
    # Provisions EBS volumes for PersistentVolumeClaims (the PostgreSQL data).
    "aws-ebs-csi-driver" = null
  }
}

data "aws_eks_addon_version" "this" {
  for_each = merge(local.before_compute_addons, local.after_compute_addons)

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "before_compute" {
  for_each = local.before_compute_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  configuration_values        = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "after_compute" {
  for_each = local.after_compute_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  configuration_values        = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}

# --- Worker nodes ------------------------------------------------------------

resource "aws_launch_template" "nodes" {
  name_prefix            = "${local.cluster_name}-nodes-"
  description            = "Worker nodes of ${local.cluster_name}"
  update_default_version = true

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = local.node_metadata_hop_limit
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.cluster_name}-node" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.cluster_name}-node" }
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = "default-"
  node_role_arn          = local.node_role_arn
  subnet_ids             = module.vpc.private_subnets

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  scaling_config {
    min_size     = 1
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  # Replace nodes one at a time; with PodDisruptionBudgets in place the
  # application stays available during node upgrades.
  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  lifecycle {
    # Changes that need a new node group (e.g. instance types) bring up the
    # replacement before the old one is drained.
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_compute,
  ]
}

# --- IAM for in-cluster controllers (EKS Pod Identity) -------------------------
# Each controller's ServiceAccount is bound to its own IAM role, so no pod uses
# the node's role. Skipped when roles cannot be created: the controllers then
# use the shared existing role through the node.

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"
  count   = local.use_existing_iam_role ? 0 : 1

  name                      = "${local.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  associations = {
    this = {
      cluster_name    = aws_eks_cluster.this.name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"
  count   = local.use_existing_iam_role ? 0 : 1

  name                            = "${local.name}-aws-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = aws_eks_cluster.this.name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}
