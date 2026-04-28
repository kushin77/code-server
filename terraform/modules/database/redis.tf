/**
 * @file terraform/modules/database/redis.tf
 * @description ElastiCache Redis cluster with replication
 * @governance OPS-001: Cache infrastructure as code
 */

# ElastiCache subnet group for multi-AZ placement
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.environment}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-redis-subnet-group"
      Tier = "cache"
    }
  )
}

# ElastiCache parameter group (mirrors docker-compose configuration)
resource "aws_elasticache_parameter_group" "redis" {
  family = "redis7"
  name   = "${var.environment}-redis-params"

  # Memory management - allkeys-lru eviction policy
  parameter {
    name  = "maxmemory-policy"
    value = var.redis_maxmemory_policy
  }

  # AOF persistence (append-only-file)
  parameter {
    name  = "appendonly"
    value = "yes"
  }

  # AOF fsync policy: everysec = good balance
  parameter {
    name  = "appendfsync"
    value = "everysec"
  }

  # Timeout for idle connections
  parameter {
    name  = "timeout"
    value = "300"
  }

  # Enable TCP keepalive
  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  # Disable RDB snapshots (using AOF instead)
  parameter {
    name  = "save"
    value = ""
  }

  # Notify keyspace events for expiration
  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-redis-params"
    }
  )
}

# ElastiCache Redis replication group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.environment}-redis"
  description          = "${var.environment} Redis cluster"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_clusters   = var.redis_num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  # Replication configuration
  automatic_failover_enabled = var.redis_automatic_failover && var.redis_num_cache_nodes > 1
  multi_az_enabled           = var.redis_num_cache_nodes > 1
  at_rest_encryption_enabled = var.enable_redis_encryption
  transit_encryption_enabled = false  # Enable only if using Redis AUTH

  # Backup configuration
  snapshot_retention_limit  = var.redis_retention_days
  snapshot_window           = "03:00-05:00"  # UTC

  # Maintenance
  maintenance_window = "mon:05:00-mon:06:00"  # UTC
  notification_topic_arn = aws_sns_topic.redis_notifications.arn

  # Logging
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  # Deletion protection
  final_snapshot_identifier = var.environment == "production" ? "${var.environment}-redis-final-${formatdate("YYYYMMDD-hhmm", timestamp())}" : null

  tags = merge(
    var.common_tags,
    {
      Name       = "${var.environment}-redis"
      Role       = "cache"
      Replication = var.redis_num_cache_nodes > 1 ? "enabled" : "disabled"
    }
  )

  depends_on = [
    aws_elasticache_parameter_group.redis,
    aws_elasticache_subnet_group.redis
  ]
}

# CloudWatch Log Group for Redis slow log
resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${var.environment}-redis-slow-log"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-redis-slow-log"
    }
  )
}

# CloudWatch Log Group for Redis engine log
resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/aws/elasticache/${var.environment}-redis-engine-log"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-redis-engine-log"
    }
  )
}

# SNS topic for Redis notifications
resource "aws_sns_topic" "redis_notifications" {
  name = "${var.environment}-redis-notifications"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-redis-notifications"
    }
  )
}

# Output Redis endpoints
output "redis_endpoint" {
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  description = "Redis primary endpoint (read-write)"
}

output "redis_reader_endpoint" {
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
  description = "Redis reader endpoint (read-only, round-robin)"
}

output "redis_port" {
  value       = aws_elasticache_replication_group.redis.port
  description = "Redis port"
}

output "redis_replication_group_id" {
  value       = aws_elasticache_replication_group.redis.id
  description = "Redis replication group ID"
}

output "redis_cluster_enabled" {
  value       = aws_elasticache_replication_group.redis.cluster_enabled
  description = "Whether cluster mode is enabled"
}
