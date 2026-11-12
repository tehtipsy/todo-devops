terraform {
  # 1.10 is the first release with native S3 state locking (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # Bucket and region come from backend.hcl (see backend.hcl.example), so the
  # same code works in any account:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "todo/eks/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
