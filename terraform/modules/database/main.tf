/**
 * @file terraform/modules/database/main.tf
 * @description Module orchestration and data sources
 * @governance OPS-001: Infrastructure as code
 */

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

# Fetch current AWS account info
data "aws_caller_identity" "current" {}

# Fetch current region info
data "aws_region" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  region         = data.aws_region.current.name
  full_environment = "${var.environment}-${var.environment == "production" ? "prod" : "dev"}"
}

# Module outputs summary
output "module_summary" {
  value = {
    environment              = var.environment
    region                   = local.region
    postgres_instance        = aws_db_instance.postgres.identifier
    postgres_version         = aws_db_instance.postgres.engine_version
    postgres_multi_az        = aws_db_instance.postgres.multi_az
    redis_replication_group  = aws_elasticache_replication_group.redis.id
    redis_num_nodes          = var.redis_num_cache_nodes
    redis_automatic_failover = aws_elasticache_replication_group.redis.automatic_failover_enabled
  }
  description = "Module deployment summary"
}
