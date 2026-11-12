# One-time setup: the S3 bucket that holds the Terraform state of the `eks`
# stack. This stack keeps its own (tiny) state locally, because the bucket it
# creates cannot store the state of the stack that creates it.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

variable "aws_region" {
  description = "AWS region for the state bucket. Use the same region as the eks stack."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names."
  type        = string
  default     = "todo"
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global: the account id and region make this one unique.
  bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Losing the state means losing track of every resource it describes.
  lifecycle {
    prevent_destroy = true
  }
}

# Every state write is kept as a version, so a corrupted or mistaken state can
# be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# The state contains secrets in plain text: refuse any request not made over TLS.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "Contents for terraform/eks/backend.hcl."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.id}"
    region = "${var.aws_region}"
  EOT
}
