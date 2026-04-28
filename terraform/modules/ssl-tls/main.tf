/**
 * @file terraform/modules/ssl-tls/main.tf
 * @description SSL/TLS module entry point
 * @governance OPS-002: Certificate infrastructure
 */

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
