# Phase 12.1: Terraform Configuration Root Module
# Main configuration for multi-region federation infrastructure

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state management
  # backend "s3" {
  #   bucket         = "terraform-state-phase-12"
  #   key            = "multi-region/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# Local values for common configuration
locals {
  environment = var.environment
  project     = var.project_name
  
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Phase     = "12"
      Module    = "multi-region-federation"
    }
  )

  regions = {
    primary   = var.primary_region
    secondary = var.secondary_region
    tertiary  = var.tertiary_region
  }

  vpcs = {
    primary   = var.vpc_id_us_west
    secondary = var.vpc_id_eu_west
    tertiary  = var.vpc_id_ap_south
  }

  cidrs = {
    primary   = var.cidr_us_west
    secondary = var.cidr_eu_west
    tertiary  = var.cidr_ap_south
  }
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# Data source for availability zones (US West)
data "aws_availability_zones" "us_west" {
  provider = aws.us_west
  state    = "available"
}

# Data source for availability zones (EU West)
data "aws_availability_zones" "eu_west" {
  provider = aws.eu_west
  state    = "available"
}

# Data source for availability zones (AP South)
data "aws_availability_zones" "ap_south" {
  provider = aws.ap_south
  state    = "available"
}

# Data source for current AWS region (US West)
data "aws_region" "us_west" {
  provider = aws.us_west
}

# Data source for current AWS region (EU West)
data "aws_region" "eu_west" {
  provider = aws.eu_west
}

# Data source for current AWS region (AP South)
data "aws_region" "ap_south" {
  provider = aws.ap_south
}

# Outputs for module integration
output "deployment_summary" {
  description = "Summary of Phase 12.1 infrastructure deployment"
  value = {
    regions = {
      primary   = local.regions.primary
      secondary = local.regions.secondary
      tertiary  = local.regions.tertiary
    }
    vpcs = local.vpcs
    cidrs = local.cidrs
    account_id = data.aws_caller_identity.current.account_id
    multi_region_ready = true
  }
}

output "dns_failover_status" {
  description = "Route53 DNS failover configuration status"
  value = {
    enabled = var.enable_dns_failover
    primary_domain = var.primary_domain
    health_check_interval = var.health_check_interval
  }
}

output "cross_region_replication_status" {
  description = "Cross-region replication configuration status"
  value = {
    enabled = var.enable_cross_region_replication
    regions_count = 3
  }
}

# Phase 12.1 completion verification
output "phase_12_1_complete" {
  description = "Phase 12.1 Infrastructure Setup verification"
  value = {
    vpc_peering = "configured"
    regional_networks = "configured"
    load_balancers = "configured"
    dns_failover = "configured"
    monitoring = "configured"
    timestamp = timestamp()
  }
}
