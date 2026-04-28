# Terraform IaC Migration Checklist for Database Services

**Objective**: Migrate from Docker Compose database services to Terraform-managed infrastructure  
**Target**: AWS RDS + ElastiCache with full IaC support  
**Effort**: 3-4 weeks (see phases below)

---

## Discovery Summary (✅ Complete)

### What We Found
- ✅ **2 primary databases**: PostgreSQL (OLTP), Redis (cache)
- ✅ **2 secondary databases**: Redpanda (event streaming), Qdrant (vector DB)
- ✅ **5 Alembic migration files** defining schema
- ✅ **Environment-driven configuration** via .env files
- ✅ **Health checks and resource limits** defined
- ✅ **Non-root service accounts** for security
- ✅ **No current Terraform database infrastructure**

### Current Gaps
- ❌ No Terraform provisioning of database services
- ❌ No Terraform secrets management
- ❌ No Terraform backup automation
- ❌ No Terraform networking for databases
- ❌ No Terraform RDS/managed database support
- ❌ No Terraform monitoring/alerting

---

## Phase 1: Foundation Setup (Week 1)

### 1.1 Create Terraform Module Structure
```
terraform/modules/database/
├── main.tf                 # Main database resources
├── variables.tf            # Input variables
├── outputs.tf              # Connection strings, endpoints
├── locals.tf               # Local values
├── rds.tf                  # PostgreSQL RDS instance
├── elasticache.tf          # Redis cluster
├── security_groups.tf      # Network security
└── README.md               # Documentation
```

**Tasks**:
- [ ] Create `terraform/modules/database/` directory structure
- [ ] Create `main.tf` with provider configuration
- [ ] Create `variables.tf` for environment-specific parameters
- [ ] Create `outputs.tf` for connection string outputs

### 1.2 PostgreSQL RDS Instance
**File**: `rds.tf`

```hcl
resource "aws_db_instance" "postgres" {
  identifier           = "${var.project_name}-postgres-${var.environment}"
  engine              = "postgres"
  engine_version      = "16.3"
  instance_class      = var.postgres_instance_class # e.g., "db.t4g.medium"
  allocated_storage   = var.postgres_storage_gb     # e.g., 100
  storage_type        = "gp3"
  storage_encrypted   = true
  
  db_name             = "kushnir_db"
  username            = "postgres"
  password            = random_password.postgres_password.result
  
  db_subnet_group_name      = aws_db_subnet_group.database.name
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  
  skip_final_snapshot = var.environment == "dev" ? true : false
  backup_retention_period = 7
  backup_window = "03:00-04:00"
  maintenance_window = "sun:04:00-sun:05:00"
  
  multi_az = var.environment == "prod" ? true : false
  
  performance_insights_enabled = true
  deletion_protection = var.environment == "prod" ? true : false
  
  tags = {
    Name = "${var.project_name}-postgres"
    Environment = var.environment
  }
}
```

**Tasks**:
- [ ] Update `engine_version` to match docker image (postgres:16)
- [ ] Set `allocated_storage` based on .env cluster config
- [ ] Add database name parameter
- [ ] Enable Multi-AZ for production
- [ ] Add backup retention policy
- [ ] Add performance insights
- [ ] Create parameter group with PostgreSQL init args

### 1.3 ElastiCache Redis Cluster
**File**: `elasticache.tf`

```hcl
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis-${var.environment}"
  engine              = "redis"
  node_type           = var.redis_node_type          # e.g., "cache.t4g.medium"
  num_cache_nodes     = var.redis_num_nodes          # e.g., 1 (prod: 3)
  engine_version      = "7.0"
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  
  port                = 6379
  automatic_failover_enabled = var.environment == "prod" ? true : false
  
  security_group_ids  = [aws_security_group.redis.id]
  subnet_group_name   = aws_elasticache_subnet_group.redis.name
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled = true
  auth_token = random_password.redis_password.result
  
  maintenance_window = "sun:05:00-sun:06:00"
  
  tags = {
    Name = "${var.project_name}-redis"
    Environment = var.environment
  }
}

resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.project_name}-redis-params"
  family = "redis7"
  
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"  # From .env.cluster
  }
  
  parameter {
    name  = "appendonly"
    value = "yes"  # From .env.cluster
  }
  
  parameter {
    name  = "maxmemory"
    value = "6291456"  # 6GB in KB
  }
}
```

**Tasks**:
- [ ] Update `engine_version` to match docker image (redis:7)
- [ ] Set `num_cache_nodes` for HA (3 for cluster mode enabled)
- [ ] Create parameter group with .env values
- [ ] Enable encryption at rest and in transit
- [ ] Add authentication token
- [ ] Set maintenance window

### 1.4 Security Groups
**File**: `security_groups.tf`

```hcl
# PostgreSQL Security Group
resource "aws_security_group" "postgres" {
  name        = "${var.project_name}-postgres-sg"
  description = "Security group for PostgreSQL database"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "PostgreSQL from application tier"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-postgres-sg"
  }
}

# Redis Security Group
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for Redis cache"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Redis from application tier"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-redis-sg"
  }
}
```

**Tasks**:
- [ ] Create security group for PostgreSQL (inbound 5432)
- [ ] Create security group for Redis (inbound 6379)
- [ ] Link to application tier security group
- [ ] Add descriptions for audit trail

### 1.5 Variables Definition
**File**: `variables.tf`

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_id" {
  description = "VPC ID for database resources"
  type        = string
}

variable "postgres_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t4g.medium"
}

variable "postgres_storage_gb" {
  description = "PostgreSQL storage size in GB"
  type        = number
  default     = 100
}

variable "redis_node_type" {
  description = "ElastiCache node type for Redis"
  type        = string
  default     = "cache.t4g.medium"
}

variable "redis_num_nodes" {
  description = "Number of Redis cache nodes"
  type        = number
  default     = 1
}

variable "postgres_backup_retention" {
  description = "PostgreSQL backup retention days"
  type        = number
  default     = 7
}
```

**Tasks**:
- [ ] Define project_name variable
- [ ] Define environment variable with validation
- [ ] Define instance class and storage variables
- [ ] Define number of nodes for failover
- [ ] Add sensible defaults

### 1.6 Outputs Definition
**File**: `outputs.tf`

```hcl
output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string for application"
  value       = "postgresql://${aws_db_instance.postgres.username}:${aws_db_instance.postgres.password}@${aws_db_instance.postgres.address}:5432/${aws_db_instance.postgres.db_name}"
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_cluster.redis.port
}

output "postgres_password_secret_arn" {
  description = "ARN of PostgreSQL password secret"
  value       = aws_secretsmanager_secret.postgres_password.arn
}

output "redis_password_secret_arn" {
  description = "ARN of Redis password secret"
  value       = aws_secretsmanager_secret.redis_password.arn
}
```

**Tasks**:
- [ ] Output RDS endpoint
- [ ] Output connection string
- [ ] Output Redis endpoint
- [ ] Output secret ARNs for credentials

**Completion Checklist for Phase 1**:
- [ ] Module directory structure created
- [ ] RDS instance defined with proper configuration
- [ ] ElastiCache cluster defined with parameter group
- [ ] Security groups created and linked
- [ ] Variables file complete with validation
- [ ] Outputs file complete
- [ ] README documenting usage
- [ ] `terraform validate` passes
- [ ] `terraform plan` shows expected resources

---

## Phase 2: Secrets & Configuration Management (Week 2)

### 2.1 AWS Secrets Manager Integration
**File**: `secrets.tf`

```hcl
resource "random_password" "postgres_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "postgres_password" {
  name_prefix             = "${var.project_name}-postgres-password-"
  recovery_window_in_days = 0  # Immediate deletion in dev
  
  tags = {
    Name = "${var.project_name}-postgres-password"
  }
}

resource "aws_secretsmanager_secret_version" "postgres_password" {
  secret_id       = aws_secretsmanager_secret.postgres_password.id
  secret_string   = random_password.postgres_password.result
}

# Similar for Redis password
resource "random_password" "redis_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "redis_password" {
  name_prefix             = "${var.project_name}-redis-password-"
  recovery_window_in_days = 0
  
  tags = {
    Name = "${var.project_name}-redis-password"
  }
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id       = aws_secretsmanager_secret.redis_password.id
  secret_string   = random_password.redis_password.result
}
```

**Tasks**:
- [ ] Create Secrets Manager secrets for PostgreSQL password
- [ ] Create Secrets Manager secrets for Redis password
- [ ] Generate random 32-character passwords
- [ ] Store in secure vault
- [ ] Document secret rotation policy

### 2.2 Environment-Specific Terraform Variables
**File**: `terraform/environments/prod/terraform.tfvars`

```hcl
project_name = "code-server"
environment  = "prod"
vpc_id       = "vpc-12345678"

postgres_instance_class     = "db.r6g.xlarge"
postgres_storage_gb         = 500
postgres_backup_retention   = 30

redis_node_type             = "cache.r6g.xlarge"
redis_num_nodes             = 3  # HA cluster
```

**Tasks**:
- [ ] Create terraform.tfvars for production
- [ ] Create terraform.tfvars for staging
- [ ] Create terraform.tfvars for development
- [ ] Document environment-specific choices
- [ ] Add to .gitignore for secrets safety

### 2.3 Database Parameter Groups
**File**: `parameters.tf`

```hcl
# PostgreSQL parameter group with Alembic-compatible settings
resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-postgres-params"
  family = "postgres16"
  
  parameter {
    name  = "client_encoding"
    value = "UTF8"  # From POSTGRES_INITDB_ARGS
  }
  
  parameter {
    name  = "max_wal_senders"
    value = "10"  # From POSTGRES_INITDB_ARGS for replication
  }
  
  parameter {
    name  = "wal_level"
    value = "replica"  # From POSTGRES_INITDB_ARGS
  }
  
  parameter {
    name  = "log_statement"
    value = "all"  # For debugging
  }
  
  tags = {
    Name = "${var.project_name}-postgres-params"
  }
}
```

**Tasks**:
- [ ] Create RDS parameter group for PostgreSQL
- [ ] Set UTF-8 encoding matching POSTGRES_INITDB_ARGS
- [ ] Set WAL replication settings
- [ ] Add logging parameters
- [ ] Document parameter rationale

### 2.4 Database Subnet Groups
**File**: `networking.tf`

```hcl
resource "aws_db_subnet_group" "database" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.database_subnets
  
  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.database_subnets
  
  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}
```

**Tasks**:
- [ ] Create RDS subnet group
- [ ] Create ElastiCache subnet group
- [ ] Add variable for subnet IDs
- [ ] Ensure multi-AZ support via multiple subnets

**Completion Checklist for Phase 2**:
- [ ] Secrets Manager integration complete
- [ ] Passwords auto-generated and stored securely
- [ ] environment-specific terraform.tfvars created
- [ ] Parameter groups defined and Alembic-compatible
- [ ] Database subnet groups created
- [ ] `terraform plan` shows all Phase 1 + Phase 2 resources
- [ ] Secrets accessible to EC2/Lambda tasks

---

## Phase 3: Backup & Monitoring (Week 3)

### 3.1 Backup Automation
**File**: `backup.tf`

```hcl
resource "aws_backup_vault" "database" {
  name = "${var.project_name}-database-backup-vault"
  
  tags = {
    Name = "${var.project_name}-database-backups"
  }
}

resource "aws_backup_plan" "database" {
  name = "${var.project_name}-database-backup-plan"
  
  rule {
    rule_name         = "daily_backup"
    target_backup_vault_name = aws_backup_vault.database.name
    schedule          = "cron(0 5 * * ? *)"  # 5 AM daily
    start_window      = 60
    completion_window = 120
    
    lifecycle {
      delete_after = 30  # Retain 30 days
    }
  }
  
  tags = {
    Name = "${var.project_name}-database-backup-plan"
  }
}
```

**Tasks**:
- [ ] Create AWS Backup vault for databases
- [ ] Define backup plan with daily schedule
- [ ] Set retention policy (7-30 days based on environment)
- [ ] Enable RDS snapshot export

### 3.2 CloudWatch Monitoring
**File**: `monitoring.tf`

```hcl
resource "aws_cloudwatch_log_group" "postgres_logs" {
  name              = "/aws/rds/${var.project_name}-postgres"
  retention_in_days = 7
  
  tags = {
    Name = "${var.project_name}-postgres-logs"
  }
}

resource "aws_cloudwatch_metric_alarm" "postgres_cpu" {
  alarm_name          = "${var.project_name}-postgres-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when PostgreSQL CPU > 80%"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }
}

resource "aws_cloudwatch_metric_alarm" "postgres_storage" {
  alarm_name          = "${var.project_name}-postgres-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5368709120"  # 5 GB
  alarm_description   = "Alert when PostgreSQL storage < 5 GB"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }
}
```

**Tasks**:
- [ ] Create CloudWatch log groups
- [ ] Create CPU utilization alarms
- [ ] Create disk space alarms
- [ ] Create replication lag alarms (if multi-AZ)
- [ ] Setup SNS notifications

**Completion Checklist for Phase 3**:
- [ ] Backup vault and plan created
- [ ] Daily backup schedule configured
- [ ] CloudWatch logs configured
- [ ] CPU, memory, and storage alarms created
- [ ] SNS topic for notifications
- [ ] Backup retention policy matches requirements

---

## Phase 4: Alembic Migration & Cutover (Week 4)

### 4.1 Migration Preparation
**Tasks**:
- [ ] Document current Docker Compose database state
- [ ] Create point-in-time backup of current PostgreSQL
- [ ] Test Alembic migrations against new RDS instance
- [ ] Verify connection string format matches expectations
- [ ] Test application against new RDS/ElastiCache endpoints

### 4.2 Connection String Generation
**Update Application Configuration**:

```hcl
# terraform/outputs.tf additions
output "database_url" {
  value = "postgresql://${aws_db_instance.postgres.username}:${random_password.postgres_password.result}@${aws_db_instance.postgres.address}:5432/kushnir_db"
  sensitive = true
}

output "redis_url" {
  value = "redis://:${random_password.redis_password.result}@${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
  sensitive = true
}
```

**Tasks**:
- [ ] Generate DATABASE_URL for application
- [ ] Generate REDIS_URL for cache
- [ ] Store in AWS Secrets Manager or Parameter Store
- [ ] Update application deployment to read from secrets
- [ ] Validate connection strings match .env.cluster format

### 4.3 Database Initialization
**Tasks**:
- [ ] Restore backup or run Alembic migrations
- [ ] Verify all 5 migration files execute successfully
- [ ] Check indexes created from optimize_database_indexes.py
- [ ] Validate schema matches current production

```bash
# Commands to run post-deployment
docker-compose exec reputation-engine alembic current
docker-compose exec reputation-engine alembic upgrade head
docker-compose exec reputation-engine psql -U postgres -c "\dt"  # List tables
```

### 4.4 Rollback Procedures
**Document Rollback Plan**:
- [ ] Document steps to revert to Docker Compose
- [ ] Keep Docker Compose files as fallback
- [ ] Document manual downgrade procedures (alembic downgrade -1)
- [ ] Test rollback in staging environment first

**Completion Checklist for Phase 4**:
- [ ] RDS PostgreSQL initialized with Alembic migrations
- [ ] ElastiCache Redis available and configured
- [ ] APPLICATION_DATABASE_URL working against RDS
- [ ] APPLICATION_REDIS_URL working against ElastiCache
- [ ] All services connecting successfully
- [ ] No data loss verified
- [ ] Alembic migrations verified to run

---

## Risk Mitigation Strategies

### Data Loss Prevention
- ✅ Daily automated backups (Phase 3)
- ✅ Multi-AZ replication for production (Phase 1)
- ✅ Point-in-time recovery capability
- ✅ Manual backup before cutover

### Performance Degradation
- ✅ Staging environment testing before production
- ✅ Connection pooling validation
- ✅ Query performance comparison (docker-compose vs RDS)
- ✅ Slow query logging enabled

### Security Risks
- ✅ Encrypted credentials in Secrets Manager (Phase 2)
- ✅ Security groups with least privilege (Phase 1)
- ✅ Encrypted storage at rest (Phase 1)
- ✅ Encrypted transmission in transit (Phase 1)
- ✅ No passwords in Terraform code

### Operational Risks
- ✅ Documented runbooks for common tasks
- ✅ Terraform state management (use S3 backend)
- ✅ Version control for all Terraform code
- ✅ Tested rollback procedures
- ✅ Clear communication plan for cutover

---

## Success Criteria

### Phase 1 Success
```
✅ terraform validate passes
✅ terraform plan shows 10-15 resources
✅ RDS instance creates successfully
✅ ElastiCache cluster creates successfully
✅ Security groups attach correctly
```

### Phase 2 Success
```
✅ Secrets created in AWS Secrets Manager
✅ environment-specific tfvars created
✅ Parameter groups match init args
✅ terraform plan includes backup resources
✅ Connection strings generated correctly
```

### Phase 3 Success
```
✅ Backup plan active
✅ CloudWatch alarms firing correctly
✅ Log groups receiving data
✅ SNS notifications working
```

### Phase 4 Success
```
✅ Alembic migrations run on new RDS
✅ Schema matches production
✅ Applications connecting successfully
✅ No data loss
✅ Performance acceptable
✅ Rollback procedure tested
```

---

## Timeline Summary

| Phase | Week | Key Deliverables | Dependencies |
|-------|------|------------------|--------------|
| **Phase 1** | Week 1 | RDS, ElastiCache, Security Groups, Variables | AWS account, VPC setup |
| **Phase 2** | Week 2 | Secrets Manager, Parameters, Subnet Groups | Phase 1 complete |
| **Phase 3** | Week 3 | Backup Plan, Monitoring, Alarms | Phase 1 & 2 complete |
| **Phase 4** | Week 4 | Migration, Testing, Cutover | Phase 1-3 complete |

---

## Quick Reference Commands

```bash
# Validate Terraform
terraform validate

# Plan Phase 1
terraform plan -target=module.database

# Apply Phase 1
terraform apply -target=module.database

# Check Alembic status on new RDS
alembic current
alembic history

# Run migrations
alembic upgrade head

# Backup current PostgreSQL (before migration)
pg_dump -h localhost -U postgres kushnir_db > backup.sql

# Restore from backup if needed
psql -h <RDS_ENDPOINT> -U postgres kushnir_db < backup.sql
```

---

## Next Steps

1. **Review**: Present this checklist to the team
2. **Refine**: Adjust instance classes and storage based on workload analysis
3. **Prepare**: Create AWS infrastructure prerequisites (VPC, subnets)
4. **Implement**: Follow phases 1-4 in order
5. **Test**: Validate at each phase before proceeding
6. **Document**: Update runbooks with new RDS/ElastiCache procedures

