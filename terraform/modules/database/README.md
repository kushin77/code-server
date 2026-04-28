# Terraform Database Module (Phase 3 - IaC Hardening)

**Date**: April 28, 2026  
**Phase**: 3 - Infrastructure as Code Hardening  
**Status**: Phase 1 Complete - RDS & ElastiCache Infrastructure  
**Owner**: Infrastructure Team

---

## Overview

This module provisions production-ready database infrastructure on AWS:
- **PostgreSQL 16** via RDS with Multi-AZ, automated backups, and Enhanced Monitoring
- **Redis 7** via ElastiCache with replication, AOF persistence, and CloudWatch logging

Replaces Docker Compose database services for production deployments.

---

## Architecture

```
┌─────────────────────────────────────────┐
│   Application Servers (Private Subnet)  │
│    [App Security Group]                 │
└────────────┬────────────────────────────┘
             │
    ┌────────┴──────────┐
    │                   │
    ▼                   ▼
┌─────────────┐   ┌─────────────┐
│ RDS PG 16   │   │ Redis 7     │
│ Multi-AZ    │   │ Replication │
│ + Backups   │   │ + AOF       │
│ + Monitoring│   │ + Logging   │
└─────────────┘   └─────────────┘
```

---

## Module Structure

```
terraform/modules/database/
├── main.tf                  # Module entry point
├── variables.tf             # Input variables (40+ options)
├── outputs.tf               # Output values
├── rds.tf                   # PostgreSQL RDS instance
├── redis.tf                 # Redis ElastiCache cluster
├── security_groups.tf       # Network security
├── iam.tf                   # IAM roles and policies
└── README.md                # This file
```

---

## Quick Start

### Basic Usage

```hcl
module "database" {
  source = "./modules/database"

  environment                    = "staging"
  vpc_id                        = aws_vpc.main.id
  private_subnet_ids            = aws_subnets.private[*].id
  application_security_group_id = aws_security_group.app.id

  # PostgreSQL sizing
  postgres_instance_class     = "db.t4g.large"
  postgres_allocated_storage  = 100
  postgres_backup_retention_days = 30

  # Redis sizing
  redis_node_type             = "cache.r7g.xlarge"
  redis_num_cache_nodes       = 2

  common_tags = {
    Project = "infrastructure-modernization"
    Phase   = "3"
  }
}
```

### Accessing Outputs

```hcl
locals {
  db = module.database.database_environment_vars
}

resource "kubernetes_secret" "database_credentials" {
  data = db
}
```

---

## Configuration Reference

### PostgreSQL (RDS)

| Variable | Default | Description |
|----------|---------|-------------|
| `postgres_instance_class` | db.t4g.large | Instance type (pricing tier) |
| `postgres_allocated_storage` | 100 GB | Initial storage allocation |
| `postgres_version` | 16.3 | PostgreSQL version |
| `postgres_backup_retention_days` | 30 | Automated backup retention |
| `postgres_deletion_protection` | true (prod), false (dev) | Prevent accidental deletion |
| `enable_postgres_encryption` | true | Encryption at rest |
| `enable_multi_az` | true | High availability mode |

### Redis (ElastiCache)

| Variable | Default | Description |
|----------|---------|-------------|
| `redis_engine_version` | 7.2 | Redis version |
| `redis_node_type` | cache.r7g.xlarge | Node type (memory tier) |
| `redis_num_cache_nodes` | 2 | Cluster size (1=single, 2+=replica) |
| `redis_automatic_failover` | true | Auto-promote replica on primary failure |
| `redis_retention_days` | 5 | Backup retention period |
| `redis_maxmemory_policy` | allkeys-lru | Eviction policy |
| `enable_redis_encryption` | true | Encryption at rest |

### Common

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | - | Environment: dev, staging, production |
| `enable_enhanced_monitoring` | true | RDS performance insights |
| `log_retention_days` | 30 | CloudWatch log retention |

---

## Environment-Specific Configuration

### Development

```hcl
# terraform/environments/dev/database.tfvars
environment                    = "dev"
postgres_instance_class        = "db.t4g.micro"  # Cost-optimized
postgres_allocated_storage     = 20
postgres_backup_retention_days = 1
postgres_deletion_protection   = false
redis_num_cache_nodes          = 1               # Single node (no replication)
enable_enhanced_monitoring     = false
log_retention_days            = 7
```

### Staging

```hcl
# terraform/environments/staging/database.tfvars
environment                    = "staging"
postgres_instance_class        = "db.t4g.medium"
postgres_allocated_storage     = 50
postgres_backup_retention_days = 14
postgres_deletion_protection   = false
redis_num_cache_nodes          = 2               # Replication for testing
enable_enhanced_monitoring     = true
log_retention_days            = 14
```

### Production

```hcl
# terraform/environments/production/database.tfvars
environment                    = "production"
postgres_instance_class        = "db.t4g.xlarge"  # Performance-optimized
postgres_allocated_storage     = 500
postgres_backup_retention_days = 30
postgres_deletion_protection   = true             # Protect against accidents
redis_num_cache_nodes          = 3                # Full replication
enable_enhanced_monitoring     = true
log_retention_days            = 90
```

---

## Deployment

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

### Step 2: Plan Database Infrastructure

```bash
# Development
terraform plan -var-file=environments/dev/database.tfvars -out=tf.plan

# Staging
terraform plan -var-file=environments/staging/database.tfvars -out=tf.plan

# Production
terraform plan -var-file=environments/production/database.tfvars -out=tf.plan
```

### Step 3: Review and Apply

```bash
# Review changes
terraform show tf.plan | less

# Apply (RDS + Redis provisioning takes ~15-20 minutes)
terraform apply tf.plan
```

### Step 4: Verify Connectivity

```bash
# Get outputs
POSTGRES_HOST=$(terraform output -raw database_outputs | jq -r '.postgres_host')
REDIS_HOST=$(terraform output -raw database_outputs | jq -r '.redis_endpoint')

# Test PostgreSQL
psql -h $POSTGRES_HOST -U postgres -d core_db -c "SELECT version();"

# Test Redis
redis-cli -h $REDIS_HOST -p 6379 ping
```

---

## Database Initialization (Alembic Migrations)

### Phase 3 Week 2 Implementation

After RDS is created, run Alembic migrations:

```bash
# 1. Get connection string from Terraform
export DATABASE_URL=$(terraform output database_environment_vars | jq -r '.POSTGRES_URL')

# 2. Run migrations
cd /path/to/repo
alembic upgrade head

# 3. Verify
alembic current
```

### Automated Migration Lambda (Planned)

Phase 3 Week 2 will include Lambda function to auto-run migrations:

```hcl
resource "aws_lambda_function" "alembic_runner" {
  # Triggered after RDS creation
  # Executes: alembic upgrade head
  # Logs: CloudWatch
  # Failures: SNS notification
}
```

---

## Security

### Network Access

- PostgreSQL (5432): Only from application security group
- Redis (6379): Only from application security group
- No public internet access (private subnets only)

### Encryption

- **At Rest**: Both PostgreSQL and Redis encrypted with AWS KMS
- **In Transit**: SSL/TLS for PostgreSQL (configurable)
- **Credentials**: Stored in AWS Secrets Manager (Phase 3 Week 2)

### IAM Roles

- **RDS Monitoring**: Minimal permissions for Enhanced Monitoring
- **Lambda Migration**: Limited database access for Alembic execution
- **Application**: Assumes role to retrieve credentials from Secrets Manager

---

## Monitoring & Alerting

### CloudWatch Dashboards

```hcl
# Created automatically:
# - RDS Performance Insights
# - Redis Slow Logs (CloudWatch Logs)
# - Engine Logs (CloudWatch Logs)
```

### Alarms (Phase 3 Week 2)

```
- RDS CPU > 80% for 5 minutes
- RDS connections > 150
- Redis memory usage > 90%
- Redis evictions > 1000/sec
- Replication lag > 100ms
```

### Notifications

```
SNS Topics:
- ${environment}-postgres-notifications
- ${environment}-redis-notifications

Subscribers:
- Ops team email
- PagerDuty integration
- Slack webhook (optional)
```

---

## Maintenance

### Automated Backups

**PostgreSQL**:
- Retention: Configurable (1-35 days)
- Window: 03:00-04:00 UTC
- Multi-AZ: Backups from secondary (no I/O impact)

**Redis**:
- Retention: Configurable (0-35 days)
- Window: 03:00-05:00 UTC
- Method: AOF (append-only file) + snapshots

### Backup Verification

```bash
# List RDS snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier ${environment}-postgres-primary

# List Redis snapshots
aws elasticache describe-snapshots \
  --replication-group-id ${environment}-redis
```

### Restore Procedure

```bash
# From RDS snapshot (Phase 3 Week 2)
terraform apply -var "restore_from_snapshot=snapshot-id"

# From Redis snapshot (Phase 3 Week 2)
terraform apply -var "restore_from_snapshot=snapshot-id"
```

---

## Disaster Recovery

### RTO/RPO Targets

| Scenario | RDS | Redis |
|----------|-----|-------|
| Node failure | < 2 min (Multi-AZ) | < 30 sec (Auto failover) |
| AZ failure | < 5 min (Multi-AZ failover) | < 30 sec (New node) |
| Data loss | 0 (backup every 5 min) | 0 (AOF persistence) |

### Recovery Testing

Monthly (Phase 3 Week 3+):
- Restore from production backup to staging
- Verify data integrity
- Test application connectivity
- Document timing and issues

---

## Troubleshooting

### PostgreSQL Connection Issues

```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier ${environment}-postgres-primary

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output database_outputs | jq -r '.postgres_security_group')

# Test connectivity
telnet $POSTGRES_HOST 5432
```

### Redis Connection Issues

```bash
# Check ElastiCache status
aws elasticache describe-replication-groups \
  --replication-group-id ${environment}-redis

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output database_outputs | jq -r '.redis_security_group')

# Test connectivity
redis-cli -h $REDIS_HOST -p 6379 ping
```

### Performance Issues

```bash
# RDS Performance Insights
aws pi describe-dimension-keys \
  --service-type RDS \
  --identifier $(terraform output database_outputs | jq -r '.postgres_arn')

# Redis Slow Log (via CloudWatch)
aws logs tail /aws/elasticache/${environment}-redis-slow-log --follow
```

---

## Scaling

### PostgreSQL Scaling

**Vertical (compute/storage)**:
```hcl
# Update instance_class variable
postgres_instance_class = "db.t4g.xlarge"  # From db.t4g.large

# Apply (multi-AZ allows zero-downtime failover)
terraform apply
```

**Horizontal (read replicas)**:
```hcl
# Phase 3 Week 3: Add read replica module
module "database_replica" {
  source = "./modules/database-replica"
  primary_id = module.database.postgres_arn
}
```

### Redis Scaling

**Vertical (memory)**:
```hcl
# Update node_type variable
redis_node_type = "cache.r7g.2xlarge"  # From cache.r7g.xlarge

# Apply (causes brief reboot)
terraform apply
```

**Horizontal (cluster mode)**:
```hcl
# Phase 3 Week 3: Enable cluster mode
enable_redis_cluster = true
redis_num_shards = 3
```

---

## Cost Optimization

### Recommendations

| Change | Savings | Impact |
|--------|---------|--------|
| Use gp3 storage | 20% | Medium (general purpose, sufficient for workload) |
| On-demand pricing | Baseline | High (no long-term commitment) |
| Reserved Instances | 30% | Low (1-year commitment available in Week 3) |
| Graviton instances (t4g/r7g) | 20% | None (already using) |

### Cost Estimation

Development:
```
RDS (db.t4g.micro):       ~$25/month
Redis (cache.t4g.micro):  ~$15/month
Storage (gp3 20GB):       ~$2/month
Total:                    ~$42/month
```

Production:
```
RDS (db.t4g.xlarge):      ~$1,200/month
Redis (cache.r7g.xlarge): ~$600/month
Storage (gp3 500GB):      ~$50/month
Total:                    ~$1,850/month
```

---

## Migration from Docker Compose

### Timeline

**Week 1** (Apr 28 - May 4): Create Terraform modules ✅  
**Week 2** (May 5 - May 11): Deploy to staging, run migrations  
**Week 3** (May 12 - May 18): Production cutover, decommission Docker services  
**Week 4** (May 19 - May 25): Monitoring & optimization

### Procedure

1. Deploy Terraform infrastructure (Week 2)
2. Run Alembic migrations on new RDS (Week 2)
3. Validate data integrity in staging (Week 2)
4. Execute blue-green deployment to production (Week 3)
5. Decommission Docker Compose services (Week 3)

---

## Related Documentation

- `DATABASE_INITIALIZATION_ANALYSIS.md` - Current database setup inventory
- `DATABASE_SERVICES_ARCHITECTURE.md` - Architecture diagrams
- `TERRAFORM_DATABASE_MIGRATION_CHECKLIST.md` - Complete 4-phase plan
- `PHASE3_EXECUTION_PLAN.md` - Phase 3 overall roadmap

---

## Support & Next Steps

**Phase 3 Week 2 (May 5-11)**:
- [ ] Deploy to staging environment
- [ ] Run Alembic migrations
- [ ] Validate application connectivity
- [ ] Create Lambda migration runner
- [ ] Set up CloudWatch alarms

**Phase 3 Week 3 (May 12-18)**:
- [ ] Production deployment
- [ ] Blue-green cutover
- [ ] Verify monitoring
- [ ] Decommission Docker services
- [ ] Cost optimization review

---

**Status**: Module ready for deployment  
**Next Action**: Deploy to staging environment (Week 2)  
**Ownership**: Infrastructure Team
