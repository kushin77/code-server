/**
 * @file terraform/database.tf
 * @description Database module integration
 * @governance OPS-001: Infrastructure as code
 * @note Phase 3 Week 1: Database initialization to IaC
 */

# Phase 3: Database Infrastructure Module
module "database" {
  count  = var.enable_database_module ? 1 : 0
  source = "./modules/database"

  # Environment configuration
  environment                   = var.environment
  vpc_id                        = var.database_vpc_id
  private_subnet_ids            = var.database_private_subnet_ids
  application_security_group_id = var.database_application_security_group_id

  # PostgreSQL configuration
  postgres_instance_class        = var.database_postgres_instance_class
  postgres_allocated_storage     = var.database_postgres_allocated_storage
  postgres_backup_retention_days = var.database_postgres_backup_retention_days
  postgres_version               = var.database_postgres_version
  postgres_deletion_protection   = var.environment == "production"
  enable_postgres_encryption     = true
  enable_multi_az                = var.environment != "dev"

  # Redis configuration
  redis_node_type          = var.database_redis_node_type
  redis_num_cache_nodes    = var.database_redis_num_cache_nodes
  redis_automatic_failover = var.environment != "dev" && var.database_redis_num_cache_nodes > 1
  redis_retention_days     = var.database_redis_retention_days
  redis_maxmemory_policy   = "allkeys-lru" # Match docker-compose configuration
  enable_redis_encryption  = true

  # Monitoring
  enable_enhanced_monitoring = var.environment != "dev"
  log_retention_days         = var.environment == "production" ? 90 : (var.environment == "staging" ? 14 : 7)

  # Common tags
  common_tags = merge(
    var.common_tags,
    {
      Module = "database"
      Phase  = "3"
      Tier   = "data"
    }
  )
}

# Export database configuration to environment variables file (for scripts)
resource "local_file" "database_env_file" {
  count    = var.enable_database_module ? 1 : 0
  filename = "${path.module}/../scripts/_common/database.env"

  content = templatefile("${path.module}/templates/database.env.tpl", {
    postgres_host = module.database[0].database_outputs.postgres_host
    postgres_port = module.database[0].database_outputs.postgres_port
    postgres_db   = module.database[0].database_outputs.postgres_database
    postgres_user = module.database[0].database_outputs.postgres_username
    redis_host    = module.database[0].database_outputs.redis_endpoint
    redis_port    = module.database[0].database_outputs.redis_port
    environment   = var.environment
  })

  lifecycle {
    ignore_changes = [content] # Don't revert if manually modified
  }

  depends_on = [module.database]
}

# Output database connection strings for application configuration
output "database_connection_info" {
  value = var.enable_database_module ? {
    postgres = {
      host              = module.database[0].database_outputs.postgres_host
      port              = module.database[0].database_outputs.postgres_port
      database          = module.database[0].database_outputs.postgres_database
      username          = module.database[0].database_outputs.postgres_username
      connection_string = "postgresql://${module.database[0].database_outputs.postgres_username}:***@${module.database[0].database_outputs.postgres_host}:${module.database[0].database_outputs.postgres_port}/${module.database[0].database_outputs.postgres_database}"
    }
    redis = {
      host              = module.database[0].database_outputs.redis_endpoint
      port              = module.database[0].database_outputs.redis_port
      connection_string = "redis://${module.database[0].database_outputs.redis_endpoint}:${module.database[0].database_outputs.redis_port}/0"
    }
  } : null
  description = "Database connection information for applications"
  sensitive   = false
}

# Output Alembic migration instructions
output "alembic_migration_instructions" {
  value = var.enable_database_module ? templatefile("${path.module}/templates/alembic-instructions.txt", {
    postgres_host = module.database[0].database_outputs.postgres_host
    postgres_port = module.database[0].database_outputs.postgres_port
    postgres_db   = module.database[0].database_outputs.postgres_database
    postgres_user = module.database[0].database_outputs.postgres_username
  }) : null
  description = "Instructions for running Alembic database migrations"
}
