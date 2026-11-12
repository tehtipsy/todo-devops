variable "aws_region" {
  description = "AWS region to deploy into. AWS Academy Learner Lab allows only us-east-1 and us-west-2."
  type        = string
  default     = "us-east-1"
}

variable "existing_iam_role_name" {
  description = <<-EOT
    Name of an existing IAM role to use for the cluster, the worker nodes and
    the in-cluster controllers, instead of creating dedicated roles. For
    sandbox accounts that forbid creating IAM roles - in AWS Academy Learner
    Lab, set "LabRole".

    Setting it also disables what needs new roles: EKS Pod Identity (the
    controllers use the node's role instead) and the keyless GitHub OIDC deploy
    role (the pipeline uses the sandbox's temporary access keys instead).
  EOT
  type        = string
  default     = null
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names."
  type        = string
  default     = "todo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must be 2-21 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Extra tags applied to every AWS resource."
  type        = map(string)
  default     = {}
}

# --- Network -----------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# --- Cluster -----------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach the public Kubernetes API endpoint. Requests are
    still authenticated through IAM. The default allows GitHub-hosted runners,
    whose addresses change constantly; narrow it to your own address when the
    pipeline does not deploy here.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "EC2 instance types for the worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND, or SPOT for roughly 60-70% cheaper nodes that AWS may reclaim at short notice."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  description = <<-EOT
    Number of worker nodes. Three t3.medium nodes fit the application, its
    autoscaling headroom and the monitoring stack: a t3.medium runs at most
    17 pods.
  EOT
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Upper bound for the node group (allows scaling up by hand without a replacement)."
  type        = number
  default     = 5
}

# --- Application -------------------------------------------------------------

variable "app_hostname" {
  description = <<-EOT
    Public hostname of the application, e.g. "todo.example.com". When set, an
    ACM certificate is requested for it and the application is served over
    HTTPS. You must be able to add DNS records for it (a subdomain: the apex
    of a domain cannot be a CNAME). null = plain HTTP on the load balancer's
    own address.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.app_hostname == null || can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.app_hostname))
    error_message = "app_hostname must be a lowercase DNS name such as todo.example.com."
  }
}

# --- CI/CD -------------------------------------------------------------------

variable "github_repository" {
  description = "GitHub repository allowed to deploy, as <owner>/<name> - the DevOps repository. Used only for the GitHub OIDC deploy role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must look like <owner>/<name>."
  }
}

variable "github_environment" {
  description = "GitHub Actions environment of the deploy job. Only jobs running in it may assume the deploy role."
  type        = string
  default     = "aws"
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    Create the IAM OIDC provider for GitHub Actions. An AWS account can hold only
    one per URL: set to false if token.actions.githubusercontent.com already
    exists in the account, and the existing one is used instead.
  EOT
  type        = bool
  default     = true
}
