provider "aws" {
  region = var.aws_region

  # Every taggable resource is labelled with where it came from.
  default_tags {
    tags = merge(var.tags, {
      Project   = var.project_name
      ManagedBy = "terraform"
      Stack     = "eks"
    })
  }
}

# Short-lived (15 minute) token for the cluster, obtained through the AWS
# provider's credentials. Unlike an `exec` block, this does not depend on the
# version of the AWS CLI installed on the machine running Terraform.
data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
