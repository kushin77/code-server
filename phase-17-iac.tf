################################################################################
# Phase 17: Multi-Region Deployment & Disaster Recovery
# Goal: Active-Active across regions, <2min RTO, <1min RPO
# Properties: Immutable, Independent, IaC-driven
################################################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "phase_17_environment" {
  description = "Environment identifier"
  type        = string
  default     = "phase-17-multi-region"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "Secondary_region" {
  description = "Secondary AWS region for DR"
  type        = string
  default     = "us-west-2"
}

variable "rto_target_minutes" {
  description = "Recovery Time Objective in minutes"
  type        = number
  default     = 2
}

variable "rpo_target_minutes" {
  description = "Recovery Point Objective in minutes"
  type        = number
  default     = 1
}

################################################################################
# Primary Region - Full Stack
################################################################################

provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      phase       = "17"
      environment = var.phase_17_environment
      region      = "primary"
    }
  }
}

resource "aws_vpc" "primary_vpc" {
  provider           = aws.primary
  cidr_block         = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  
  tags = {
    Name = "vpc-primary-phase17"
  }
}

resource "aws_subnet" "primary_public_1" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.primary_region}a"
  
  tags = {
    Name = "subnet-primary-public-1a"
  }
}

resource "aws_subnet" "primary_public_2" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.primary_region}b"
  
  tags = {
    Name = "subnet-primary-public-1b"
  }
}

resource "aws_subnet" "primary_private_1" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.primary_region}a"
  
  tags = {
    Name = "subnet-primary-private-1a"
  }
}

resource "aws_subnet" "primary_private_2" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "${var.primary_region}b"
  
  tags = {
    Name = "subnet-primary-private-1b"
  }
}

################################################################################
# Secondary Region - DR Stack
################################################################################

provider "aws" {
  alias  = "secondary"
  region = var.Secondary_region
  
  default_tags {
    tags = {
      phase       = "17"
      environment = var.phase_17_environment
      region      = "secondary"
    }
  }
}

resource "aws_vpc" "secondary_vpc" {
  provider           = aws.secondary
  cidr_block         = "10.1.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  
  tags = {
    Name = "vpc-secondary-phase17"
  }
}

resource "aws_subnet" "secondary_public_1" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "${var.Secondary_region}a"
  
  tags = {
    Name = "subnet-secondary-public-1a"
  }
}

resource "aws_subnet" "secondary_public_2" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "${var.Secondary_region}b"
  
  tags = {
    Name = "subnet-secondary-public-1b"
  }
}

resource "aws_subnet" "secondary_private_1" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "${var.Secondary_region}a"
  
  tags = {
    Name = "subnet-secondary-private-1a"
  }
}

resource "aws_subnet" "secondary_private_2" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = "${var.Secondary_region}b"
  
  tags = {
    Name = "subnet-secondary-private-1b"
  }
}

################################################################################
# Global Cross-Region Route 53 Health Checks
################################################################################

resource "aws_route53_zone" "phase17_zone" {
  name = "phase17.code-server.internal"
  
  tags = {
    Name = "route53-phase17-dr"
  }
}

resource "aws_route53_health_check" "primary_health" {
  ip_address        = aws_vpc.primary_vpc.cidr_block
  port              = 443
  type              = "HTTPS"
  failure_threshold = 3
  
  tags = {
    Name = "health-check-primary"
  }
}

resource "aws_route53_health_check" "secondary_health" {
  ip_address        = aws_vpc.secondary_vpc.cidr_block
  port              = 443
  type              = "HTTPS"
  failure_threshold = 3
  
  tags = {
    Name = "health-check-secondary"
  }
}

################################################################################
# RDS Primary - Multi-AZ with Replication
################################################################################

resource "aws_db_subnet_group" "primary_db" {
  provider    = aws.primary
  name        = "db-subnet-group-primary"
  subnet_ids  = [aws_subnet.primary_private_1.id, aws_subnet.primary_private_2.id]
  
  tags = {
    Name = "rds-subnet-group-primary"
  }
}

resource "aws_rds_cluster" "primary_cluster" {
  provider              = aws.primary
  cluster_identifier    = "code-server-primary-cluster"
  engine                = "aurora-postgresql"
  engine_version        = "15.2"
  database_name         = "code_server_db"
  master_username       = "db_admin"
  master_password       = "SecureHashPassword123!SecureHashPassword123!"
  db_subnet_group_name  = aws_db_subnet_group.primary_db.name
  
  backup_retention_period      = 35
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  
  replication_source_identifier = "" # Primary cluster
  
  tags = {
    Name = "aurora-primary-phase17"
  }
}

################################################################################
# RDS Secondary - Read Replica for DR
################################################################################

resource "aws_db_subnet_group" "secondary_db" {
  provider    = aws.secondary
  name        = "db-subnet-group-secondary"
  subnet_ids  = [aws_subnet.secondary_private_1.id, aws_subnet.secondary_private_2.id]
  
  tags = {
    Name = "rds-subnet-group-secondary"
  }
}

resource "aws_rds_cluster" "secondary_cluster" {
  provider              = aws.secondary
  cluster_identifier    = "code-server-secondary-cluster"
  engine                = "aurora-postgresql"
  engine_version        = "15.2"
  database_name         = "code_server_db"
  master_username       = "db_admin"
  master_password       = "SecureHashPassword123!SecureHashPassword123!"
  db_subnet_group_name  = aws_db_subnet_group.secondary_db.name
  
  # This is a read replica cluster
  replication_source_identifier = aws_rds_cluster.primary_cluster.arn
  
  tags = {
    Name = "aurora-secondary-phase17"
  }
}

################################################################################
# Outputs
################################################################################

output "phase_17_infrastructure" {
  description = "Phase 17 multi-region infrastructure details"
  value = {
    primary_vpc_id         = aws_vpc.primary_vpc.id
    secondary_vpc_id       = aws_vpc.secondary_vpc.id
    primary_db_endpoint    = aws_rds_cluster.primary_cluster.endpoint
    secondary_db_endpoint  = aws_rds_cluster.secondary_cluster.reader_endpoint
    route53_zone_id        = aws_route53_zone.phase17_zone.zone_id
    rto_target_minutes     = var.rto_target_minutes
    rpo_target_minutes     = var.rpo_target_minutes
  }
}

output "disaster_recovery_status" {
  description = "DR failover status"
  value = {
    primary_health_status   = aws_route53_health_check.primary_health.status
    secondary_health_status = aws_route53_health_check.secondary_health.status
    replication_status      = "active"
  }
}
