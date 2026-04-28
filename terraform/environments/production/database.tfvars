# Production environment database configuration
# Location: terraform/environments/production/database.tfvars
# Usage: terraform apply -var-file=environments/production/database.tfvars
# WARNING: Changes to production database configuration should follow change control process

environment                    = "production"
postgres_instance_class        = "db.t4g.xlarge"
postgres_allocated_storage     = 500
postgres_backup_retention_days = 30
postgres_deletion_protection   = true
postgres_version               = "16.3"

redis_node_type          = "cache.r7g.xlarge"
redis_num_cache_nodes    = 3
redis_automatic_failover = true
redis_retention_days     = 30

enable_redis_encryption    = true
enable_postgres_encryption = true
enable_enhanced_monitoring = true
enable_multi_az            = true
log_retention_days         = 90

common_tags = {
  Environment = "production"
  Project     = "infrastructure-modernization"
  Phase       = "3"
  ManagedBy   = "Terraform"
  CostCenter  = "operations"
  Criticality = "P0"
}
