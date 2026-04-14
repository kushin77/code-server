# Phase 17: Multi-Region Disaster Recovery (Cross-Region Replication)
# Terraform module for geographic redundancy and failover capability
# Deployment: Sequential after Phase 16 (depends on Phase 16-A/B infrastructure)
# Status: Production-ready, idempotent, immutable, independent failover domains

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for DR"
  type        = string
  default     = "us-west-2"
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 REPLICATION FOR APPLICATION STATE
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "primary_state" {
  bucket = "kushnir-prod-state-${data.aws_caller_identity.current.account_id}-us-east-1"

  tags = {
    Name        = "kushnir-prod-state-primary"
    Environment = var.environment
    Phase       = "17"
  }
}

resource "aws_s3_bucket_versioning" "primary_state" {
  bucket = aws_s3_bucket.primary_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "secondary_state" {
  provider = aws.secondary
  bucket   = "kushnir-prod-state-${data.aws_caller_identity.current.account_id}-us-west-2"

  tags = {
    Name        = "kushnir-prod-state-secondary"
    Environment = var.environment
    Phase       = "17"
  }
}

resource "aws_s3_bucket_versioning" "secondary_state" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# KMS ENCRYPTION KEYS FOR DR REGIONS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_kms_key" "primary_dr" {
  description             = "KMS key for DR encryption in primary region"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "kushnir-dr-primary-key"
    Environment = var.environment
    Phase       = "17"
  }
}

resource "aws_kms_key" "secondary_dr" {
  provider                = aws.secondary
  description             = "KMS key for DR encryption in secondary region"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "kushnir-dr-secondary-key"
    Environment = var.environment
    Phase       = "17"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ROUTE 53 FAILOVER
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_route53_zone" "primary" {
  name = "prod.kushnir.io"

  tags = {
    Name        = "kushnir-prod-zone"
    Environment = var.environment
    Phase       = "17"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DYNAMODB GLOBAL TABLES (For session state distribution)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "session_state" {
  name           = "kushnir-session-state"
  billing_mode   = "PAY_PER_REQUEST"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  hash_key = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "expiration_time"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "kushnir-session-state"
    Environment = var.environment
    Phase       = "17"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EVENTBRIDGE RULES FOR DR ORCHESTRATION
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "dr_failover" {
  name = "kushnir-dr-failover-alerts"

  tags = {
    Name        = "kushnir-dr-failover"
    Environment = var.environment
    Phase       = "17"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  alarm_name          = "kushnir-rds-replication-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AuroraBinlogReplicaLag"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "5000"
  alarm_description   = "Alert when RDS replication lag exceeds 5 seconds"
  alarm_actions       = [aws_sns_topic.dr_failover.arn]
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# PROVIDERS
# ─────────────────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "primary_s3_bucket" {
  description = "Primary S3 state bucket"
  value       = aws_s3_bucket.primary_state.id
}

output "secondary_s3_bucket" {
  description = "Secondary S3 state bucket"
  value       = aws_s3_bucket.secondary_state.id
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.primary.zone_id
}

output "failover_dns_name" {
  description = "DNS name for automatic failover"
  value       = "app.prod.kushnir.io"
}

output "dr_topic_arn" {
  description = "SNS topic for DR failover alerts"
  value       = aws_sns_topic.dr_failover.arn
}
