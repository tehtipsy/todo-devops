# TLS certificate for the application's public hostname.
#
# AWS Certificate Manager issues and renews it for free once you prove you own
# the domain: add the CNAME record from the `acm_validation_record` output at
# your DNS provider. The AWS Load Balancer Controller then finds the issued
# certificate by hostname and serves it on the load balancer's HTTPS listener
# (deploy with APP_HOSTNAME set - see scripts/deploy.sh).
#
# Skipped when app_hostname is null: the application is then served over plain
# HTTP on the load balancer's own address.

resource "aws_acm_certificate" "app" {
  count = var.app_hostname == null ? 0 : 1

  domain_name       = var.app_hostname
  validation_method = "DNS"

  # A replacement certificate (e.g. a new hostname) is issued before the old
  # one is removed, so the listener is never left without one.
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  # A single-name certificate has exactly one validation record.
  acm_validation = var.app_hostname == null ? null : one(aws_acm_certificate.app[0].domain_validation_options)
}
