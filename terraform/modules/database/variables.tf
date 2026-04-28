/**
 * @file terraform/modules/database/variables.tf
 * @description Phase 3: Database infrastructure variables
 * @governance OPS-001: Infrastructure as code for all persistent services
 */

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "vpc_id" {
  description = "VPC ID for database resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for database deployment"
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets required for multi-AZ deployment."
  }
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ deployment for PostgreSQL"
  type        = bool
  default     = true
}

variable "postgres_instance_class" {
  description = "RDS instance type for PostgreSQL"
  type        = string
  default     = "db.t4g.large"
  validation {
    condition     = can(regex("^db\\.", var.postgres_instance_class))
    error_message = "Must be valid RDS instance class."
  }
}

variable "postgres_allocated_storage" {
  description = "Allocated storage for PostgreSQL (GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.postgres_allocated_storage >= 20 && var.postgres_allocated_storage <= 65536
    error_message = "Storage must be between 20 and 65536 GB."
  }
}

variable "postgres_backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
  validation {
    condition     = var.postgres_backup_retention_days >= 1 && var.postgres_backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16.3"
}

variable "postgres_deletion_protection" {
  description = "Enable deletion protection for production"
  type        = bool
  default     = true
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.2"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r7g.xlarge"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes (1 = single node, 2+ = replication)"
  type        = number
  default     = 2
  validation {
    condition     = var.redis_num_cache_nodes >= 1 && var.redis_num_cache_nodes <= 6
    error_message = "Number of nodes must be between 1 and 6."
  }
}

variable "redis_automatic_failover" {
  description = "Enable automatic failover for Redis"
  type        = bool
  default     = true
}

variable "redis_retention_days" {
  description = "Days to retain Redis automatic backups"
  type        = number
  default     = 5
  validation {
    condition     = var.redis_retention_days >= 0 && var.redis_retention_days <= 35
    error_message = "Retention days must be between 0 and 35."
  }
}

variable "redis_maxmemory_policy" {
  description = "Redis maxmemory-policy"
  type        = string
  default     = "allkeys-lru"
  validation {
    condition     = contains(["volatile-lru", "volatile-lfu", "volatile-random", "volatile-ttl", "allkeys-lru", "allkeys-lfu", "allkeys-random", "noeviction"], var.redis_maxmemory_policy)
    error_message = "Must be a valid Redis maxmemory-policy."
  }
}

variable "application_security_group_id" {
  description = "Security group ID for application servers"
  type        = string
}

variable "enable_redis_encryption" {
  description = "Enable encryption at rest for Redis"
  type        = bool
  default     = true
}

variable "enable_postgres_encryption" {
  description = "Enable encryption at rest for PostgreSQL"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "infrastructure-modernization"
    ManagedBy   = "Terraform"
    Phase       = "3"
    CreatedDate = "2026-04-28"
  }
}

variable "enable_redpanda" {
  description = "Enable Redpanda/MSK deployment"
  type        = bool
  default     = false
}

variable "enable_qdrant" {
  description = "Enable Qdrant deployment"
  type        = bool
  default     = false
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Must be a valid CloudWatch retention period."
  }
}
