data "aws_availability_zones" "available" {
  # Skip Local Zones and Wavelength Zones, which EKS does not support.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name         = var.project_name
  cluster_name = "${var.project_name}-eks"
  # EKS needs subnets in at least two Availability Zones.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Two tiers per Availability Zone:
#   public  - the Application Load Balancer and the NAT gateway
#   private - the worker nodes; they reach the internet (image pulls) via NAT
#             and are never directly reachable from it
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway = true
  # One NAT gateway instead of one per AZ: an AZ outage would cut the private
  # subnets off from the internet, but it halves the largest fixed network cost.
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Lets the AWS Load Balancer Controller discover where to place load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
