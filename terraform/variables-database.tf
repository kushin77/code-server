/**
 * @file terraform/variables-database.tf
 * @description Database module variables (add to root terraform/variables.tf)
 * @governance OPS-001: Infrastructure as code configuration
 */

# PostgreSQL (RDS) Configuration Variables
variable "database_postgres_instance_class" {
  description = "RDS instance type for PostgreSQL"
  type        = string
  default     = "db.t4g.medium"
}

variable "database_postgres_allocated_storage" {
  description = "Allocated storage for PostgreSQL (GB)"
  type        = number
  default     = 50
  validation {
    condition     = var.database_postgres_allocated_storage >= 20 && var.database_postgres_allocated_storage <= 65536
    error_message = "PostgreSQL storage must be between 20 and 65536 GB."
  }
}

variable "database_postgres_backup_retention_days" {
  description = "Number of days to retain PostgreSQL automated backups"
  type        = number
  default     = 14
  validation {
    condition     = var.database_postgres_backup_retention_days >= 1 && var.database_postgres_backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "database_postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16.3"
}

# Redis (ElastiCache) Configuration Variables
variable "database_redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r7g.large"
}

variable "database_redis_num_cache_nodes" {
  description = "Number of cache nodes for Redis (1=single, 2+=replication)"
  type        = number
  default     = 2
  validation {
    condition     = var.database_redis_num_cache_nodes >= 1 && var.database_redis_num_cache_nodes <= 6
    error_message = "Redis cluster size must be between 1 and 6 nodes."
  }
}

variable "database_redis_retention_days" {
  description = "Days to retain Redis automatic backups"
  type        = number
  default     = 5
  validation {
    condition     = var.database_redis_retention_days >= 0 && var.database_redis_retention_days <= 35
    error_message = "Redis backup retention must be between 0 and 35 days."
  }
}

# Feature Flags
variable "enable_database_encryption" {
  description = "Enable encryption at rest for all database services"
  type        = bool
  default     = true
}

variable "enable_database_monitoring" {
  description = "Enable enhanced monitoring for databases"
  type        = bool
  default     = true
}
