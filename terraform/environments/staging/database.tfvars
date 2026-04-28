# Staging environment database configuration
# Location: terraform/environments/staging/database.tfvars
# Usage: terraform apply -var-file=environments/staging/database.tfvars

environment                    = "staging"
postgres_instance_class        = "db.t4g.medium"
postgres_allocated_storage     = 50
postgres_backup_retention_days = 14
postgres_deletion_protection   = false
postgres_version               = "16.3"

redis_node_type          = "cache.r7g.large"
redis_num_cache_nodes    = 2
redis_automatic_failover = true
redis_retention_days     = 7

enable_redis_encryption    = true
enable_postgres_encryption = true
enable_enhanced_monitoring = true
enable_multi_az            = true
log_retention_days         = 14

common_tags = {
  Environment = "staging"
  Project     = "infrastructure-modernization"
  Phase       = "3"
  ManagedBy   = "Terraform"
  CostCenter  = "engineering"
}
