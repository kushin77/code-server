# Phase 12.1: VPC Peering Configuration for Multi-Region Networking
# This file configures VPC peering across 3+ regions for inter-region communication

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider configurations for multiple regions
provider "aws" {
  alias  = "us_west"
  region = var.primary_region

  default_tags {
    tags = {
      Environment = "production"
      Phase       = "12"
      Component   = "vpc-peering"
    }
  }
}

provider "aws" {
  alias  = "eu_west"
  region = var.secondary_region

  default_tags {
    tags = {
      Environment = "production"
      Phase       = "12"
      Component   = "vpc-peering"
    }
  }
}

provider "aws" {
  alias  = "ap_south"
  region = var.tertiary_region

  default_tags {
    tags = {
      Environment = "production"
      Phase       = "12"
      Component   = "vpc-peering"
    }
  }
}

# VPC Peering Connection: US West ← → EU West
resource "aws_vpc_peering_connection" "us_eu" {
  provider      = aws.us_west
  vpc_id        = var.vpc_id_us_west
  peer_vpc_id   = var.vpc_id_eu_west
  peer_region   = var.secondary_region
  auto_accept   = false

  tags = {
    Name = "peering-us-eu"
  }
}

# Accept VPC Peering Connection from EU side
resource "aws_vpc_peering_connection_accepter" "us_eu" {
  provider                  = aws.eu_west
  vpc_peering_connection_id = aws_vpc_peering_connection.us_eu.id
  auto_accept               = true

  tags = {
    Name = "peering-us-eu-accepter"
  }
}

# VPC Peering Connection: US West ← → AP South
resource "aws_vpc_peering_connection" "us_ap" {
  provider      = aws.us_west
  vpc_id        = var.vpc_id_us_west
  peer_vpc_id   = var.vpc_id_ap_south
  peer_region   = var.tertiary_region
  auto_accept   = false

  tags = {
    Name = "peering-us-ap"
  }
}

# Accept VPC Peering from AP side
resource "aws_vpc_peering_connection_accepter" "us_ap" {
  provider                  = aws.ap_south
  vpc_peering_connection_id = aws_vpc_peering_connection.us_ap.id
  auto_accept               = true

  tags = {
    Name = "peering-us-ap-accepter"
  }
}

# VPC Peering Connection: EU West ← → AP South
resource "aws_vpc_peering_connection" "eu_ap" {
  provider      = aws.eu_west
  vpc_id        = var.vpc_id_eu_west
  peer_vpc_id   = var.vpc_id_ap_south
  peer_region   = var.tertiary_region
  auto_accept   = false

  tags = {
    Name = "peering-eu-ap"
  }
}

# Accept VPC Peering from AP side
resource "aws_vpc_peering_connection_accepter" "eu_ap" {
  provider                  = aws.ap_south
  vpc_peering_connection_id = aws_vpc_peering_connection.eu_ap.id
  auto_accept               = true

  tags = {
    Name = "peering-eu-ap-accepter"
  }
}

# Route table entries for US West
resource "aws_route" "us_to_eu" {
  provider                  = aws.us_west
  route_table_id            = var.route_table_id_us_west
  destination_cidr_block    = var.cidr_eu_west
  vpc_peering_connection_id = aws_vpc_peering_connection.us_eu.id
}

resource "aws_route" "us_to_ap" {
  provider                  = aws.us_west
  route_table_id            = var.route_table_id_us_west
  destination_cidr_block    = var.cidr_ap_south
  vpc_peering_connection_id = aws_vpc_peering_connection.us_ap.id
}

# Route table entries for EU West
resource "aws_route" "eu_to_us" {
  provider                  = aws.eu_west
  route_table_id            = var.route_table_id_eu_west
  destination_cidr_block    = var.cidr_us_west
  vpc_peering_connection_id = aws_vpc_peering_connection.us_eu.id
}

resource "aws_route" "eu_to_ap" {
  provider                  = aws.eu_west
  route_table_id            = var.route_table_id_eu_west
  destination_cidr_block    = var.cidr_ap_south
  vpc_peering_connection_id = aws_vpc_peering_connection.eu_ap.id
}

# Route table entries for AP South
resource "aws_route" "ap_to_us" {
  provider                  = aws.ap_south
  route_table_id            = var.route_table_id_ap_south
  destination_cidr_block    = var.cidr_us_west
  vpc_peering_connection_id = aws_vpc_peering_connection.us_ap.id
}

resource "aws_route" "ap_to_eu" {
  provider                  = aws.ap_south
  route_table_id            = var.route_table_id_ap_south
  destination_cidr_block    = var.cidr_eu_west
  vpc_peering_connection_id = aws_vpc_peering_connection.eu_ap.id
}

# Network ACL rules to allow traffic across peering connections
resource "aws_network_acl_rule" "peering_inbound" {
  for_each = {
    "us_from_eu" = {
      network_acl_id = var.nacl_id_us_west
      cidr_block     = var.cidr_eu_west
    }
    "us_from_ap" = {
      network_acl_id = var.nacl_id_us_west
      cidr_block     = var.cidr_ap_south
    }
    "eu_from_us" = {
      network_acl_id = var.nacl_id_eu_west
      cidr_block     = var.cidr_us_west
    }
    "eu_from_ap" = {
      network_acl_id = var.nacl_id_eu_west
      cidr_block     = var.cidr_ap_south
    }
    "ap_from_us" = {
      network_acl_id = var.nacl_id_ap_south
      cidr_block     = var.cidr_us_west
    }
    "ap_from_eu" = {
      network_acl_id = var.nacl_id_ap_south
      cidr_block     = var.cidr_eu_west
    }
  }

  network_acl_id = each.value.network_acl_id
  rule_number    = 100 + index(keys(aws_network_acl_rule.peering_inbound), each.key)
  protocol       = "-1"  # All protocols
  rule_action    = "allow"
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

# Output peering connection IDs for reference
output "peering_connection_us_eu_id" {
  value       = aws_vpc_peering_connection.us_eu.id
  description = "VPC Peering Connection ID for US-West to EU-West"
}

output "peering_connection_us_ap_id" {
  value       = aws_vpc_peering_connection.us_ap.id
  description = "VPC Peering Connection ID for US-West to AP-South"
}

output "peering_connection_eu_ap_id" {
  value       = aws_vpc_peering_connection.eu_ap.id
  description = "VPC Peering Connection ID for EU-West to AP-South"
}
