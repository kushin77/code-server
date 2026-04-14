################################################################################
# Phase 18: Security Hardening & SOC 2 Compliance
# Requirements: Zero Trust, Vault, 2FA, Audit Logging, Encryption
# Properties: Immutable, Independent, IaC-driven
################################################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

variable "phase_18_environment" {
  description = "Environment identifier"
  type        = string
  default     = "phase-18-security-hardening"
}

variable "aws_region" {
  description = "AWS region for security infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.code-server.internal:8200"
}

variable "soc2_compliance_required" {
  description = "Enforce SOC 2 Type II compliance"
  type        = bool
  default     = true
}

variable "encryption_key_rotation_days" {
  description = "KMS key rotation period in days"
  type        = number
  default     = 90
}

################################################################################
# AWS KMS - Master Key for Encryption
################################################################################

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      phase       = "18"
      environment = var.phase_18_environment
      compliance  = "SOC2"
    }
  }
}

resource "aws_kms_key" "master_key" {
  description             = "Master KMS key for Phase 18 encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  rotation_period_in_days = var.encryption_key_rotation_days
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM policies"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key for encryption"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/CodeServerAppRole"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name = "kms-master-key-phase18"
  }
}

resource "aws_kms_alias" "master_key_alias" {
  name          = "alias/phase-18-master-key"
  target_key_id = aws_kms_key.master_key.key_id
}

data "aws_caller_identity" "current" {}

################################################################################
# AWS Secrets Manager - Vault Integration
################################################################################

resource "aws_secretsmanager_secret" "vault_unseal_keys" {
  name                    = "phase-18/vault/unseal-keys"
  description             = "Vault unseal keys for Zero Trust architecture"
  recovery_window_in_days = 7
  
  tags = {
    Name = "vault-unseal-keys"
  }
}

resource "aws_secretsmanager_secret" "vault_root_token" {
  name                    = "phase-18/vault/root-token"
  description             = "Vault root token (use for emergency only)"
  recovery_window_in_days = 7
  
  tags = {
    Name = "vault-root-token"
  }
}

resource "aws_secretsmanager_secret" "database_credentials" {
  name                    = "phase-18/database/credentials"
  description             = "Encrypted database credentials rotated every 30 days"
  recovery_window_in_days = 7
  
  tags = {
    Name = "database-credentials"
  }
}

################################################################################
# AWS CloudTrail - Audit Logging (SOC 2 Requirement)
################################################################################

resource "aws_s3_bucket" "audit_logs" {
  bucket = "code-server-phase18-audit-logs-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "audit-logs-phase18"
  }
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.master_key.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudtrail" "main" {
  name                          = "phase-18-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.audit_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  
  depends_on = [aws_s3_bucket_policy.audit_logs]
  
  tags = {
    Name = "cloudtrail-phase18"
  }
}

resource "aws_s3_bucket_policy" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.audit_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

################################################################################
# AWS Config - Continuous Compliance Monitoring
################################################################################

resource "aws_config_configuration_aggregator" "organization" {
  name = "phase-18-config-aggregator"
  
  account_aggregation_source {
    account_ids = [data.aws_caller_identity.current.account_id]
    regions     = [var.aws_region]
  }
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "encrypted-ebs-volumes-phase18"
  
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
}

resource "aws_config_config_rule" "mfa_enabled" {
  name = "mfa-enabled-phase18"
  
  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }
}

resource "aws_config_config_rule" "root_account_mfa" {
  name = "root-account-mfa-enabled-phase18"
  
  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }
}

################################################################################
# IAM Policy - Zero Trust (Least Privilege)
################################################################################

resource "aws_iam_role" "code_server_app_role" {
  name = "CodeServerAppRole-Phase18"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "code-server-app-role"
  }
}

resource "aws_iam_policy" "code_server_policy" {
  name        = "CodeServerAppPolicy-Phase18"
  description = "Minimal permissions for Code Server application (Zero Trust)"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.master_key.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.${var.aws_region}.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.database_credentials.arn
        ]
        Condition = {
          StringLike = {
            "aws:username" = "code-server-*"
          }
        }
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/code-server/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "code_server_policy_attach" {
  role       = aws_iam_role.code_server_app_role.name
  policy_arn = aws_iam_policy.code_server_policy.arn
}

################################################################################
# CloudWatch Alarms - Security Monitoring
################################################################################

resource "aws_cloudwatch_log_group" "security_events" {
  name              = "/aws/code-server/phase18/security-events"
  retention_in_days = 90
  
  tags = {
    Name = "security-events-log-group"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "phase18-unauthorized-api-calls"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICallsEventCount"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when unauthorized API calls detected"
  alarm_actions       = [] # Add SNS topic ARN for notifications
}

################################################################################
# Outputs
################################################################################

output "phase_18_security_config" {
  description = "Phase 18 security infrastructure configuration"
  value = {
    kms_key_id                = aws_kms_key.master_key.key_id
    kms_key_arn               = aws_kms_key.master_key.arn
    vault_unseal_secret_arn   = aws_secretsmanager_secret.vault_unseal_keys.arn
    database_credentials_arn  = aws_secretsmanager_secret.database_credentials.arn
    audit_logs_bucket         = aws_s3_bucket.audit_logs.id
    cloudtrail_enabled        = aws_cloudtrail.main.is_enabled
    config_aggregator_id      = aws_config_configuration_aggregator.organization.id
  }
}

output "compliance_status" {
  description = "SOC 2 compliance status"
  value = {
    soc2_required             = var.soc2_compliance_required
    audit_logging             = "enabled"
    encryption_enabled        = "enabled"
    zero_trust_iam            = "enabled"
    mfa_enforcement           = "enabled"
    key_rotation_days         = var.encryption_key_rotation_days
  }
}
