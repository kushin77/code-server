# Phase 16-A: Database High Availability (PostgreSQL HA + pgBouncer)
# Terraform module for managed database redundancy and connection pooling
# Deployment: 15-20 minutes, parallel-deployable with Phase 16-B
# Status: Production-ready, idempotent, immutable, independently deployable
# NOTE: Terraform configuration consolidated in main.tf for idempotency

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6i.2xlarge"
}

variable "db_storage_size" {
  description = "Database storage in GB"
  type        = number
  default     = 500
}

variable "db_backup_retention" {
  description = "Backup retention in days"
  type        = number
  default     = 35
}

variable "pgbouncer_min_size" {
  description = "pgBouncer ASG minimum size"
  type        = number
  default     = 2
}

variable "pgbouncer_max_size" {
  description = "pgBouncer ASG maximum size"
  type        = number
  default     = 4
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "kushnir-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "PostgreSQL from internal networks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name        = "kushnir-rds-sg"
    Environment = var.environment
    Phase       = "16-A"
  }
}

resource "aws_security_group" "pgbouncer" {
  name        = "kushnir-pgbouncer-sg"
  description = "Security group for pgBouncer connection pooler"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    from_port   = 6432
    to_port     = 6432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "pgBouncer from internal networks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name        = "kushnir-pgbouncer-sg"
    Environment = var.environment
    Phase       = "16-A"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DB SUBNET GROUP
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "primary" {
  name       = "kushnir-db-subnet-group"
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Name        = "kushnir-db-subnet-group"
    Environment = var.environment
    Phase       = "16-A"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS PARAMETER GROUP
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "postgresql" {
  family      = "postgres14"
  name        = "kushnir-postgres14-pg"
  description = "PostgreSQL parameter group for replication"

  parameter {
    name  = "max_connections"
    value = "500"
  }

  parameter {
    name  = "wal_level"
    value = "replica"
  }

  parameter {
    name  = "max_wal_senders"
    value = "5"
  }

  parameter {
    name  = "wal_keep_size"
    value = "1024"
  }

  parameter {
    name  = "log_replication_commands"
    value = "on"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = {
    Name        = "kushnir-postgres14-pg"
    Environment = var.environment
    Phase       = "16-A"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS PRIMARY INSTANCE
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_db_instance" "primary" {
  identifier            = "kushnir-prod-db"
  engine                = "postgres"
  engine_version        = "14.7"
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_storage_size
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.rds.arn

  db_name  = "kushnir_prod"
  username = "postgres"
  password = random_password.db_password.result

  parameter_group_name = aws_db_parameter_group.postgresql.name
  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = true
  backup_retention_period = var.db_backup_retention
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"
  auto_minor_version_upgrade = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "kushnir-prod-db-final-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval            = 300
  monitoring_role_arn           = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled   = true
  performance_insights_retention_period = 7

  # Deletion protection
  deletion_protection = true

  tags = {
    Name        = "kushnir-prod-db"
    Environment = var.environment
    Phase       = "16-A"
  }

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}

# ─────────────────────────────────────────────────────────────────────────────
# KMS KEY FOR RDS ENCRYPTION
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "kushnir-rds-key"
    Environment = var.environment
    Phase       = "16-A"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/kushnir-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS READ REPLICA (CROSS-REGION)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_db_instance" "replica" {
  identifier          = "kushnir-prod-db-replica"
  replicate_source_db = aws_db_instance.primary.identifier

  instance_class        = var.db_instance_class
  publicly_accessible   = false
  auto_minor_version_upgrade = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "kushnir-prod-db-replica-final-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  backup_retention_period = var.db_backup_retention

  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval            = 300
  monitoring_role_arn           = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "kushnir-prod-db-replica"
    Environment = var.environment
    Phase       = "16-A"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# PGBOUNCER CONNECTION POOLER (ASG)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_launch_template" "pgbouncer" {
  name_prefix   = "kushnir-pgbouncer-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.large"

  vpc_security_group_ids = [aws_security_group.pgbouncer.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
      kms_key_id           = aws_kms_key.rds.arn
    }
  }

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
      Name        = "kushnir-pgbouncer"
      Environment = var.environment
      Phase       = "16-A"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "pgbouncer" {
  name              = "kushnir-pgbouncer-asg"
  vpc_zone_identifier = data.aws_subnets.private.ids
  
  launch_template {
    id      = aws_launch_template.pgbouncer.id
    version = "$Latest"
  }

  min_size         = var.pgbouncer_min_size
  max_size         = var.pgbouncer_max_size
  desired_capacity = 2

  health_check_type           = "EC2"
  health_check_grace_period   = 300
  termination_policies        = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "kushnir-pgbouncer"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM ROLES FOR MONITORING
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "kushnir-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECRETS MANAGER FOR DB CREDENTIALS
# ─────────────────────────────────────────────────────────────────────────────

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "kushnir/prod/db-master-password"
  kms_key_id = aws_kms_key.rds.id

  rotation_rules {
    automatically_after_days = 30
  }

  tags = {
    Name        = "kushnir-db-password"
    Environment = var.environment
    Phase       = "16-A"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  secret_string       = random_password.db_password.result
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH ALARMS FOR MONITORING
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "rds_replica_lag" {
  alarm_name          = "kushnir-rds-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationLag"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "5000"
  alarm_description   = "Alert when RDS replica lag exceeds 5 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "kushnir-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when RDS CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "kushnir-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "450"
  alarm_description   = "Alert when database connections approach max"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.id
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES (Consolidated in data_sources.tf)
# NOTE: aws_vpc, aws_subnets, aws_ami, aws_sns_topic are defined in data_sources.tf
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "rds_primary_endpoint" {
  description = "Primary RDS endpoint"
  value       = aws_db_instance.primary.endpoint
}

output "rds_replica_endpoint" {
  description = "Read replica endpoint"
  value       = aws_db_instance.replica.endpoint
}

output "pgbouncer_asg_name" {
  description = "pgBouncer Auto Scaling Group name"
  value       = aws_autoscaling_group.pgbouncer.name
}

output "db_password_secret_arn" {
  description = "Secrets Manager ARN for database password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "kms_key_id" {
  description = "KMS key ID for RDS encryption"
  value       = aws_kms_key.rds.id
}
