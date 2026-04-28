/**
 * @file terraform/modules/database/rds.tf
 * @description PostgreSQL RDS instance with Alembic migration support
 * @governance OPS-001: Database infrastructure as code
 * @note Alembic migrations executed post-RDS creation via python script
 */

# Database subnet group for multi-AZ placement
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.environment}-postgres-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-postgres-subnet-group"
      Tier = "database"
    }
  )

  lifecycle {
    ignore_changes = [tags["LastModified"]]
  }
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgres" {
  identifier = "${var.environment}-postgres-primary"

  # Engine and version
  engine         = "postgres"
  engine_version = var.postgres_version

  # Instance sizing
  instance_class     = var.postgres_instance_class
  allocated_storage  = var.postgres_allocated_storage
  storage_type       = "gp3"
  storage_encrypted  = var.enable_postgres_encryption
  iops               = 3000
  storage_throughput = 125

  # Credentials (use AWS Secrets Manager in production)
  db_name  = "core_db"
  username = "postgres"
  password = random_password.postgres_password.result

  # High availability
  multi_az = var.enable_multi_az

  # Networking
  db_subnet_group_name      = aws_db_subnet_group.postgres.name
  publicly_accessible       = false
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.environment}-postgres-final-snapshot-${formatdate("YYYYMMDD-hhmm", timestamp())}" : null

  # Backup and maintenance
  backup_retention_period  = var.postgres_backup_retention_days
  backup_window            = "03:00-04:00"         # UTC
  maintenance_window       = "mon:04:00-mon:05:00" # UTC
  copy_tags_to_snapshot    = true
  delete_automated_backups = var.environment != "production"

  # Performance and monitoring
  performance_insights_enabled          = var.enable_enhanced_monitoring
  performance_insights_retention_period = 7
  monitoring_interval                   = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn                   = var.enable_enhanced_monitoring ? aws_iam_role.rds_monitoring.arn : null
  enabled_cloudwatch_logs_exports       = ["postgresql"]

  # Database configuration
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Deletion protection
  deletion_protection = var.postgres_deletion_protection

  # Options
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  apply_immediately           = var.environment != "production"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-postgres-primary"
      Tier = "database"
      Role = "oltp"
    }
  )

  depends_on = [aws_db_subnet_group.postgres]
}

# PostgreSQL Parameter Group (mirrors docker-compose configuration)
resource "aws_db_parameter_group" "postgres" {
  family = "postgres16"
  name   = "${var.environment}-postgres-params"

  # Alembic compatibility settings
  parameter {
    name  = "max_connections"
    value = "200"
  }

  # WAL configuration for replication support
  parameter {
    name  = "max_wal_senders"
    value = "10"
  }

  parameter {
    name  = "wal_keep_size"
    value = "1024" # MB
  }

  # Performance tuning
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}" # 25% of instance memory
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "{DBInstanceClassMemory/63963}" # 1.6% of instance memory
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory/2730}" # 50% of instance memory
  }

  # Logging for troubleshooting
  parameter {
    name  = "log_statement"
    value = var.environment == "production" ? "ddl" : "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = var.environment == "production" ? "5000" : "1000" # ms
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-postgres-params"
    }
  )
}

# Generate secure random password
resource "random_password" "postgres_password" {
  length  = 32
  special = true

  override_special = "!#$%&*()-_=+[]{}<>:?"

  lifecycle {
    ignore_changes = all # Don't rotate password once set
  }
}

# Output RDS endpoint
output "postgres_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "PostgreSQL RDS endpoint (host:port)"
  sensitive   = false
}

output "postgres_host" {
  value       = aws_db_instance.postgres.address
  description = "PostgreSQL RDS hostname"
}

output "postgres_port" {
  value       = aws_db_instance.postgres.port
  description = "PostgreSQL RDS port"
}

output "postgres_database" {
  value       = aws_db_instance.postgres.db_name
  description = "Default PostgreSQL database name"
}

output "postgres_username" {
  value       = aws_db_instance.postgres.username
  description = "PostgreSQL master username"
}

output "postgres_password" {
  value       = random_password.postgres_password.result
  description = "PostgreSQL master password"
  sensitive   = true
}

output "postgres_arn" {
  value       = aws_db_instance.postgres.arn
  description = "PostgreSQL RDS ARN"
}
