/**
 * @file terraform/modules/database/outputs.tf
 * @description Database module outputs
 */

output "database_outputs" {
  value = {
    # PostgreSQL
    postgres_endpoint       = aws_db_instance.postgres.endpoint
    postgres_host           = aws_db_instance.postgres.address
    postgres_port           = aws_db_instance.postgres.port
    postgres_database       = aws_db_instance.postgres.db_name
    postgres_username       = aws_db_instance.postgres.username
    postgres_arn            = aws_db_instance.postgres.arn
    postgres_security_group = aws_security_group.postgres.id

    # Redis
    redis_endpoint          = aws_elasticache_replication_group.redis.primary_endpoint_address
    redis_reader_endpoint   = aws_elasticache_replication_group.redis.reader_endpoint_address
    redis_port              = aws_elasticache_replication_group.redis.port
    redis_replication_group = aws_elasticache_replication_group.redis.id
    redis_security_group    = aws_security_group.redis.id

    # Configuration
    postgres_parameter_group = aws_db_parameter_group.postgres.name
    redis_parameter_group    = aws_elasticache_parameter_group.redis.name
  }
  description = "All database service outputs"
}

# Exported environment variables for application configuration
output "database_environment_vars" {
  value = {
    # PostgreSQL connection
    POSTGRES_HOST     = aws_db_instance.postgres.address
    POSTGRES_PORT     = tostring(aws_db_instance.postgres.port)
    POSTGRES_DB       = aws_db_instance.postgres.db_name
    POSTGRES_USER     = aws_db_instance.postgres.username
    POSTGRES_PASSWORD = random_password.postgres_password.result # Store in secrets manager
    POSTGRES_URL      = "postgresql://${aws_db_instance.postgres.username}:${random_password.postgres_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"

    # Redis connection
    REDIS_HOST = aws_elasticache_replication_group.redis.primary_endpoint_address
    REDIS_PORT = tostring(aws_elasticache_replication_group.redis.port)
    REDIS_URL  = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}/0"
  }
  description = "Environment variables for application configuration"
  sensitive   = false # Marked per environment variable
}

# Detailed resource outputs
output "postgres_details" {
  value = {
    id                = aws_db_instance.postgres.id
    arn               = aws_db_instance.postgres.arn
    endpoint          = aws_db_instance.postgres.endpoint
    engine            = aws_db_instance.postgres.engine
    engine_version    = aws_db_instance.postgres.engine_version
    instance_class    = aws_db_instance.postgres.instance_class
    allocated_storage = aws_db_instance.postgres.allocated_storage
    storage_type      = aws_db_instance.postgres.storage_type
    multi_az          = aws_db_instance.postgres.multi_az
    backup_retention  = aws_db_instance.postgres.backup_retention_period
  }
  description = "Detailed PostgreSQL RDS outputs"
}

output "redis_details" {
  value = {
    id                 = aws_elasticache_replication_group.redis.id
    arn                = aws_elasticache_replication_group.redis.arn
    engine             = aws_elasticache_replication_group.redis.engine
    engine_version     = aws_elasticache_replication_group.redis.engine_version
    node_type          = aws_elasticache_replication_group.redis.node_type
    num_cache_clusters = aws_elasticache_replication_group.redis.num_cache_clusters
    automatic_failover = aws_elasticache_replication_group.redis.automatic_failover_enabled
    multi_az           = aws_elasticache_replication_group.redis.multi_az_enabled
    cluster_enabled    = aws_elasticache_replication_group.redis.cluster_enabled
  }
  description = "Detailed Redis ElastiCache outputs"
}
