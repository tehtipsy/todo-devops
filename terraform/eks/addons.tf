# Cluster add-ons installed with Helm.

# Turns Kubernetes Ingress resources into AWS Application Load Balancers. The
# application's Ingress (k8s/overlays/aws) uses the `alb` IngressClass that
# this chart creates.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.2"
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = aws_eks_cluster.this.name
    region      = var.aws_region
    vpcId       = module.vpc.vpc_id
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
    # Not used by the application; disabled so the controller never calls the
    # WAF and Shield APIs (Shield is denied outright in Learner Lab).
    enableShield = false
    enableWaf    = false
    enableWafv2  = false
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { memory = "256Mi" }
    }
  })]

  # Nodes, add-ons and the controller's IAM role must exist first.
  depends_on = [
    aws_eks_node_group.default,
    aws_eks_addon.after_compute,
    module.lb_controller_pod_identity,
  ]
}

# Resource metrics for the HorizontalPodAutoscaler and `kubectl top`.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"

  values = [yamlencode({
    resources = {
      requests = { cpu = "20m", memory = "48Mi" }
      limits   = { memory = "128Mi" }
    }
  })]

  # The load balancer controller registers a webhook for Services; installing
  # another chart while that webhook has no ready pod would be rejected.
  depends_on = [helm_release.aws_load_balancer_controller]
}
