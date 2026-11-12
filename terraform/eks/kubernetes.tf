# Cluster-level Kubernetes objects that belong to the platform rather than to
# the application: storage, the application namespace, and the permissions of
# the CI/CD deploy identity.

locals {
  app_namespace  = "todo"
  deployer_group = "todo-deployers"
}

# New EKS clusters have no default StorageClass, so the PostgreSQL
# PersistentVolumeClaim (which names none) would stay Pending without this.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.after_compute]
}

# The application namespace is created here, not by the pipeline, so that the
# deploy identity needs no permission to create namespaces. The labels match
# k8s/base/namespace.yaml, which the pipeline applies on top.
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = local.app_namespace
    labels = {
      "app.kubernetes.io/part-of"                  = "todo"
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/audit"           = "restricted"
      # The load balancer controller adds a readiness gate to every pod, so a
      # rollout only proceeds once the new pod is healthy in the ALB target group.
      "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled"
    }
  }

  lifecycle {
    # kubectl records its last-applied configuration as an annotation.
    ignore_changes = [metadata[0].annotations]
  }

  # Destroy order matters: deleting the namespace deletes the Ingress (and so the
  # ALB) and the PersistentVolumeClaim (and so the EBS volume). That cleanup is
  # done by the load balancer controller and the EBS CSI driver, so the
  # namespace has to go before they do - otherwise the ALB and volume are
  # orphaned and the VPC cannot be deleted.
  depends_on = [
    aws_eks_node_group.default,
    aws_eks_addon.after_compute,
    helm_release.aws_load_balancer_controller,
    module.ebs_csi_pod_identity,
    kubernetes_storage_class_v1.gp3,
  ]
}

# --- RBAC for the GitHub Actions deploy role ---------------------------------
# The role is mapped to the `todo-deployers` group by its EKS access entry
# (github-oidc.tf). The group may manage everything inside the `todo` namespace
# and, cluster-wide, only read and update that one namespace object. Skipped
# when there is no deploy role (existing_iam_role_name is set).

resource "kubernetes_role_binding_v1" "deployers_admin" {
  count = local.github_deploy_role ? 1 : 0

  metadata {
    name      = "todo-deployers-admin"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    # Built-in role: full control of namespaced resources, but no access to
    # the namespace itself, its resource quotas or anything cluster-wide.
    name = "admin"
  }

  subject {
    kind      = "Group"
    name      = local.deployer_group
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_cluster_role_v1" "deployers_namespace" {
  count = local.github_deploy_role ? 1 : 0

  metadata {
    name = "todo-deployers-namespace"
  }

  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = [local.app_namespace]
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "deployers_namespace" {
  count = local.github_deploy_role ? 1 : 0

  metadata {
    name = "todo-deployers-namespace"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.deployers_namespace[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = local.deployer_group
    api_group = "rbac.authorization.k8s.io"
  }
}
