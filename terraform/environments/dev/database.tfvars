# Development environment database configuration
# Location: terraform/environments/dev/database.tfvars
# Usage: terraform apply -var-file=environments/dev/database.tfvars

environment                    = "dev"
postgres_instance_class        = "db.t4g.micro"
postgres_allocated_storage     = 20
postgres_backup_retention_days = 1
postgres_deletion_protection   = false
postgres_version               = "16.3"

redis_node_type          = "cache.t4g.micro"
redis_num_cache_nodes    = 1
redis_automatic_failover = false
redis_retention_days     = 0

enable_redis_encryption    = false
enable_postgres_encryption = true
enable_enhanced_monitoring = false
enable_multi_az            = false
log_retention_days         = 7

common_tags = {
  Environment = "dev"
  Project     = "infrastructure-modernization"
  Phase       = "3"
  ManagedBy   = "Terraform"
  CostCenter  = "engineering"
}
