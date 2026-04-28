/**
 * @file terraform/modules/database/security_groups.tf
 * @description Security groups for PostgreSQL and Redis
 * @governance OPS-001: Network security via infrastructure code
 */

# Security group for PostgreSQL RDS
resource "aws_security_group" "postgres" {
  name        = "${var.environment}-postgres-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-postgres-sg"
    }
  )
}

# Allow inbound PostgreSQL traffic from application servers
resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = aws_security_group.postgres.id

  description              = "PostgreSQL from application servers"
  from_port                = 5432
  to_port                  = 5432
  ip_protocol              = "tcp"
  referenced_security_group_id = var.application_security_group_id

  tags = {
    Name = "postgres-from-app"
  }
}

# Allow outbound traffic (implicit allow all by default, but explicit for clarity)
resource "aws_vpc_security_group_egress_rule" "postgres_egress" {
  security_group_id = aws_security_group.postgres.id

  description      = "Allow all outbound"
  ip_protocol      = "-1"
  cidr_ipv4        = "0.0.0.0/0"

  tags = {
    Name = "postgres-egress-all"
  }
}

# Security group for Redis ElastiCache
resource "aws_security_group" "redis" {
  name        = "${var.environment}-redis-sg"
  description = "Security group for Redis ElastiCache"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-redis-sg"
    }
  )
}

# Allow inbound Redis traffic from application servers
resource "aws_vpc_security_group_ingress_rule" "redis_from_app" {
  security_group_id = aws_security_group.redis.id

  description              = "Redis from application servers"
  from_port                = 6379
  to_port                  = 6379
  ip_protocol              = "tcp"
  referenced_security_group_id = var.application_security_group_id

  tags = {
    Name = "redis-from-app"
  }
}

# Allow outbound traffic
resource "aws_vpc_security_group_egress_rule" "redis_egress" {
  security_group_id = aws_security_group.redis.id

  description      = "Allow all outbound"
  ip_protocol      = "-1"
  cidr_ipv4        = "0.0.0.0/0"

  tags = {
    Name = "redis-egress-all"
  }
}

# Output security group IDs
output "postgres_security_group_id" {
  value       = aws_security_group.postgres.id
  description = "PostgreSQL security group ID"
}

output "redis_security_group_id" {
  value       = aws_security_group.redis.id
  description = "Redis security group ID"
}
