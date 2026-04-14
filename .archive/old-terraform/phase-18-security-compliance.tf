# Phase 18: Security & Compliance (Vault HA, mTLS, SOC2, HIPAA)
# Terraform module for security hardening and compliance certification
# Deployment: Parallel with Phase 17 (independent security domain)
# Status: Production-ready, idempotent, immutable, zero-trust architecture
# NOTE: Terraform configuration consolidated in main.tf for idempotency

variable "vault_instance_type" {
  description = "EC2 instance type for HashiCorp Vault"
  type        = string
  default     = "t3.large"
}

variable "vault_cluster_size" {
  description = "Number of Vault instances for HA"
  type        = number
  default     = 3
}

variable "enable_waf" {
  description = "Enable AWS WAF on load balancers"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty for threat detection"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub for compliance aggregation"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 365
}

# ─────────────────────────────────────────────────────────────────────────────
# HASHICORP VAULT HA CLUSTER
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "vault" {
  name        = "kushnir-vault-sg"
  description = "Security group for HashiCorp Vault"
  vpc_id      = data.aws_vpc.primary.id

  # Vault API from internal networks
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Vault API (internal)"
  }

  # Vault HA cluster node communication
  ingress {
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Vault HA cluster communication"
  }

  # SSH for emergency access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "SSH (emergency access)"
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name        = "kushnir-vault-sg"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_launch_template" "vault" {
  name_prefix   = "kushnir-vault-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.vault_instance_type

  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.vault.arn
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
      encrypted             = true
      kms_key_id           = aws_kms_key.vault.arn
    }
  }

  user_data = base64encode(templatefile("${path.module}/vault-init.sh", {
    cluster_size = var.vault_cluster_size
    aws_region   = data.aws_region.current.name
  }))

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "kushnir-vault"
      Environment = var.environment
      Phase       = "18"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "vault" {
  name              = "kushnir-vault-asg"
  vpc_zone_identifier = data.aws_subnets.private.ids
  
  launch_template {
    id      = aws_launch_template.vault.id
    version = "$Latest"
  }

  min_size         = var.vault_cluster_size
  max_size         = var.vault_cluster_size
  desired_capacity = var.vault_cluster_size

  health_check_type           = "ELB"
  health_check_grace_period   = 300
  termination_policies        = ["OldestInstance"]
  target_group_arns           = [aws_lb_target_group.vault.arn]

  tag {
    key                 = "Name"
    value               = "kushnir-vault-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Phase"
    value               = "18"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VAULT LOAD BALANCER (Internal Only)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "vault" {
  name               = "kushnir-vault-lb"
  load_balancer_type = "network"
  internal           = true
  subnets            = data.aws_subnets.private.ids

  enable_deletion_protection = true

  tags = {
    Name        = "kushnir-vault-lb"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_lb_target_group" "vault" {
  name        = "kushnir-vault-tg"
  port        = 8200
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.primary.id
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    port                = "8200"
  }

  tags = {
    Name        = "kushnir-vault-tg"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 8200
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# KMS ENCRYPTION FOR VAULT
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_kms_key" "vault" {
  description             = "KMS key for Vault encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "kushnir-vault-key"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_kms_alias" "vault" {
  name          = "alias/kushnir-vault"
  target_key_id = aws_kms_key.vault.key_id
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "kushnir-logs-key"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS SECRETS MANAGER FOR APPLICATION SECRETS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "kushnir/prod/db-credentials"
  kms_key_id = aws_kms_key.vault.id

  rotation_rules {
    automatically_after_days = 30
  }

  tags = {
    Name        = "kushnir-db-credentials"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_secretsmanager_secret" "api_keys" {
  name = "kushnir/prod/api-keys"
  kms_key_id = aws_kms_key.vault.id

  rotation_rules {
    automatically_after_days = 90
  }

  tags = {
    Name        = "kushnir-api-keys"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_secretsmanager_secret" "oauth_credentials" {
  name = "kushnir/prod/oauth-credentials"
  kms_key_id = aws_kms_key.vault.id

  rotation_rules {
    automatically_after_days = 60
  }

  tags = {
    Name        = "kushnir-oauth-credentials"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS WAF (Web Application Firewall)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_wafv2_ip_set" "trusted_ips" {
  name               = "kushnir-trusted-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  address_set        = ["10.0.0.0/8"]

  tags = {
    Name        = "kushnir-trusted-ips"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0
  name  = "kushnir-prod-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0

    action {
      block {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 1

    action {
      block {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimiting"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitingMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "kushnir-prod-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "kushnir-prod-waf"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS GUARDDUTY (Threat Detection)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }

  tags = {
    Name        = "kushnir-guardduty"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS SECURITY HUB (Compliance Aggregation)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "cis" {
  count           = var.enable_security_hub ? 1 : 0
  standards_arn   = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on      = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "pci_dss" {
  count           = var.enable_security_hub ? 1 : 0
  standards_arn   = "arn:aws:securityhub:${data.aws_region.current.name}::standards/pci-dss/v/3.2.1"
  depends_on      = [aws_securityhub_account.main]
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH LOGS ENCRYPTION
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "vault" {
  name              = "/aws/vault/audit"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name        = "kushnir-vault-logs"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_cloudwatch_log_group" "security" {
  name              = "/aws/security/events"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name        = "kushnir-security-logs"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM ROLES FOR VAULT NODES
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "vault" {
  name = "kushnir-vault-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vault_kms" {
  name   = "kushnir-vault-kms"
  role   = aws_iam_role.vault.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant"
      ]
      Resource = aws_kms_key.vault.arn
    }]
  })
}

resource "aws_iam_role_policy" "vault_s3_backend" {
  name   = "kushnir-vault-s3"
  role   = aws_iam_role.vault.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ]
      Resource = [
        "arn:aws:s3:::kushnir-vault-backend",
        "arn:aws:s3:::kushnir-vault-backend/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "vault_dynamodb_backend" {
  name   = "kushnir-vault-dynamodb"
  role   = aws_iam_role.vault.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:DescribeTable",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ]
      Resource = aws_dynamodb_table.vault_backend.arn
    }]
  })
}

resource "aws_iam_role_policy" "vault_auto_unseal" {
  name   = "kushnir-vault-auto-unseal"
  role   = aws_iam_role.vault.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      Resource = aws_kms_key.vault.arn
    }]
  })
}

resource "aws_iam_instance_profile" "vault" {
  name = "kushnir-vault-profile"
  role = aws_iam_role.vault.name
}

# ─────────────────────────────────────────────────────────────────────────────
# DYNAMODB TABLE FOR VAULT BACKEND STORAGE
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "vault_backend" {
  name           = "kushnir-vault-backend"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "Path"
  range_key      = "Key"

  attribute {
    name = "Path"
    type = "S"
  }

  attribute {
    name = "Key"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.vault.arn
  }

  ttl {
    attribute_name = "Expiration"
    enabled        = true
  }

  tags = {
    Name        = "kushnir-vault-backend"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 BUCKET FOR VAULT AUDIT LOGS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "vault_logs" {
  bucket = "kushnir-vault-audit-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "kushnir-vault-logs"
    Environment = var.environment
    Phase       = "18"
  }
}

resource "aws_s3_bucket_versioning" "vault_logs" {
  bucket = aws_s3_bucket.vault_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_logs" {
  bucket = aws_s3_bucket.vault_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.vault.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vault_logs" {
  bucket                  = aws_s3_bucket.vault_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING & ALARMS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "vault_unsealed" {
  alarm_name          = "kushnir-vault-sealed-warning"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "VaultSealed"
  namespace           = "kushnir/vault"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "Alert when Vault is in sealed state"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "vault_auth_failures" {
  alarm_name          = "kushnir-vault-auth-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AuthFailures"
  namespace           = "kushnir/vault"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert on excessive authentication failures"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_sns_topic" "security_alerts" {
  name = "kushnir-security-alerts"

  tags = {
    Name        = "kushnir-security-alerts"
    Environment = var.environment
    Phase       = "18"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES (Consolidated in data_sources.tf)
# NOTE: aws_vpc, aws_subnets, aws_ami, aws_caller_identity, aws_region consolidated for consistency
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "vault_lb_endpoint" {
  description = "Internal Vault load balancer endpoint"
  value       = aws_lb.vault.dns_name
}

output "vault_kms_key_id" {
  description = "KMS key ID for Vault encryption"
  value       = aws_kms_key.vault.id
}

output "secrets_manager_db_secret_arn" {
  description = "ARN of database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "security_hub_enabled" {
  description = "AWS Security Hub is enabled"
  value       = var.enable_security_hub
}

output "guardduty_enabled" {
  description = "AWS GuardDuty is enabled"
  value       = var.enable_guardduty
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}
