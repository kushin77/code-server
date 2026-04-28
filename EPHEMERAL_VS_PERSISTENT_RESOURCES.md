# Infrastructure Resource Classification: Ephemeral vs Persistent

**Phase**: Phase 3 Week 2  
**Date**: April 28, 2026  
**Status**: Framework Complete  
**Audience**: DevOps, Infrastructure, Application Teams

---

## Executive Summary

This document provides a comprehensive classification framework for all infrastructure resources managed by this deployment, categorizing them as **ephemeral** (short-lived, recreatable), **persistent** (long-lived, must be preserved), or **hybrid** (both characteristics).

### Key Definitions

| Category | Definition | Recovery | Backup Required |
|----------|-----------|----------|-----------------|
| **Ephemeral** | Short-lived resources that can be recreated from code/configuration | Automatic (redeploy) | No |
| **Persistent** | Long-lived resources whose loss causes data/service loss | Manual (restore from backup) | Yes |
| **Hybrid** | Resources with both ephemeral and persistent characteristics | Depends on content type | Selective |

---

## 1. Resource Classification Matrix

### 1.1 Database Layer

#### PostgreSQL 16 (AWS RDS)
```
Classification: PERSISTENT
Environment Deployment: RDS Managed Service
```

**Characteristics**:
- ✅ Persistent: Contains application state, user data, audit logs
- ❌ NOT Recreatable: Loss = data loss
- ⚠️ Time-Sensitive: Downtime impacts all applications
- ✅ Automated Backups: AWS RDS handles retention

**Lifecycle Policy**:
```
Backup Retention:
  Development:   1 day (low cost, fast recovery acceptable)
  Staging:       14 days (test data can be recreated, faster recovery)
  Production:    30 days (legal/compliance requirement)

Automatic Backup Window: Daily 02:00-04:00 UTC
Point-in-Time Recovery (PITR): Enabled (35-day window in production)
Multi-AZ Failover: Enabled (99.95% availability SLA)
```

**Disaster Recovery**:
- ✅ RDS automated backups to S3
- ✅ Cross-region backup replication (production)
- ✅ Point-in-time restore to any moment in 35-day window
- ✅ Read replicas for production (0 RTO possible with promotion)
- ⏳ Manual snapshots taken before major schema changes

**Cost Impact**:
```
Storage: $0.23/GB/month (PostgreSQL storage)
Backup: $0.095/GB/month (RDS backup storage)
Monitoring: Included in RDS pricing
Development: ~$18/month
Staging: ~$32/month
Production: ~$180/month
```

**Migration Path** (from Docker → RDS):
```
Phase 1: RDS deployment (new cluster created)
Phase 2: Alembic migration validation (schema check)
Phase 3: Data cutover (dump from docker-compose pg → RDS)
Phase 4: Application endpoint update (environment variables)
Phase 5: Docker Compose postgres service shutdown
Phase 6: Verification (2 weeks in production)
```

---

#### Redis 7 (AWS ElastiCache)
```
Classification: HYBRID (Persistent + Ephemeral)
Environment Deployment: ElastiCache Managed Service
```

**Characteristics**:
- ⚠️ Hybrid: Contains session data (ephemeral) + cache (ephemeral) + configuration (persistent)
- ✅ Recreatable: Cache data can be regenerated
- ❌ NOT Fully Recreatable: Session data loss = user re-login
- ✅ Automated Failover: Multi-node cluster provides HA

**Lifecycle Policy**:
```
AOF (Append-Only File) Persistence:
  Development:   Disabled (low cost, ephemeral sessions OK)
  Staging:       Enabled (validate persistence behavior)
  Production:    Enabled (data recovery capability)

Persistence Window: Every 60 seconds (configurable)
Replication:
  Development:   Single node (cache only)
  Staging:       2-node cluster (automatic failover)
  Production:    3-node cluster (automatic failover + read scaling)

Backup:
  Automatic snapshots: Daily at 03:00 UTC
  Retention: 5 most recent snapshots
  Manual snapshots: Before major config changes
```

**Disaster Recovery**:
- ✅ AOF persistence enabled (production/staging)
- ✅ Automatic cluster failover (multi-node)
- ✅ Snapshot-based recovery available
- ⚠️ Session loss acceptable (users re-login)
- ✅ Cache regeneration acceptable (performance impact only)
- ⏳ Manual snapshot restore if needed

**Cost Impact**:
```
Nodes:
  Development: cache.t4g.micro (1 node) = $25/month
  Staging: cache.r7g.large × 2 (2 nodes) = $150/month
  Production: cache.r7g.xlarge × 3 (3 nodes) = $1,050/month

Backup Storage: $0.029/GB/month
Data Transfer: $0.02/GB (cross-AZ replication)
```

**Hybrid Behavior Management**:
```
Session Data (EPHEMERAL):
  TTL: 30 days maximum
  Loss Impact: User re-login required
  Recovery: Not needed (ephemeral)

Cache Data (EPHEMERAL):
  TTL: 1-24 hours depending on content type
  Loss Impact: Performance degradation only
  Recovery: Automatic regeneration by applications

Configuration Data (PERSISTENT):
  TTL: None (persistent until explicitly deleted)
  Loss Impact: Application configuration loss
  Recovery: Restore from snapshot or manual reconfiguration
```

---

#### Redpanda (Message Queue)
```
Classification: HYBRID (Persistent + Ephemeral)
Environment Deployment: Docker Compose (transitional)
Status: Migrate to AWS MSK in Phase 3 Week 3+
```

**Current Characteristics**:
- ⚠️ Hybrid: Contains event log (persistent) + consumer offsets (persistent)
- ✅ Recreatable from source events
- ⏳ Consumer lag tolerance: 24 hours acceptable
- ✅ Auto-replication within cluster

**Lifecycle Policy** (Current Docker):
```
Persistence: Enabled (log retention)
Log Retention:
  Development: 1 day
  Staging: 7 days
  Production: 30 days

Replication Factor: 3
Retention Policy: Size-based (100GB) + time-based
```

**Planned Migration** (Phase 3 Week 3+):
```
Target: AWS MSK (Managed Streaming Kafka)
Benefits:
  - Automated backups
  - Automatic failover
  - Scaling without downtime
  - CloudWatch integration

Timeline: Week of May 12, 2026
Recovery: Log-based recovery from MSK backups
```

---

#### Qdrant (Vector Database)
```
Classification: HYBRID (Persistent + Regeneratable)
Environment Deployment: Docker Compose (transitional)
Status: Migrate to AWS Custom Service in Phase 3 Week 3+
```

**Current Characteristics**:
- ⚠️ Hybrid: Contains vector embeddings (regeneratable) + indexes (regeneratable)
- ✅ Regeneratable: Embeddings can be re-indexed from source documents
- ⏳ Regeneration cost: 2-4 hours for full re-index
- ✅ Auto-replication within cluster

**Lifecycle Policy** (Current Docker):
```
Persistence: Disk-based
Replication: 3 replicas
Snapshot Frequency: Daily
Retention: 14 most recent snapshots
```

**Planned Migration** (Phase 3 Week 3+):
```
Target: AWS ECS + EBS + RDS for metadata
Benefits:
  - Managed backup/restore
  - Automatic failover
  - Better scaling

Timeline: Week of May 19, 2026
Recovery: Re-index from source vectors (acceptable delay)
```

---

### 1.2 Storage Layer

#### Docker Volumes
```
Classification: EPHEMERAL (in Docker Compose) → PERSISTENT (migrated)
Current State: Docker Compose named volumes
```

**Volume Inventory**:
```
postgres-data/
  Purpose: PostgreSQL persistent storage
  Size: 20GB (dev) - 500GB (prod)
  Classification: PERSISTENT
  Backup: RDS automated backups (Phase 3 Week 2)
  
redis-data/
  Purpose: Redis AOF backup files
  Size: 5GB (dev) - 100GB (prod)
  Classification: HYBRID
  Backup: ElastiCache snapshots (Phase 3 Week 2)
  
app-logs/
  Purpose: Application log aggregation
  Size: 50GB average
  Classification: EPHEMERAL (rotated weekly)
  Retention: 4 weeks
  Cleanup: Automated via logrotate
  
cache-data/
  Purpose: Shared cache mount
  Size: 10GB
  Classification: EPHEMERAL
  Retention: 1 week
  Cleanup: Weekly purge script
  
artifacts/
  Purpose: Build artifacts, generated files
  Size: 30GB
  Classification: EPHEMERAL
  Retention: 30 days
  Cleanup: CI/CD cleanup job
```

**Migration Strategy** (Phase 3 Week 2+):
```
Ephemeral Volumes → S3 for Archive:
  - Terraform can automatically sync to S3
  - Retention policies enforced via bucket lifecycle
  - Cost: $0.023/GB/month in S3 Standard

Persistent Volumes → AWS EBS:
  - RDS handles PostgreSQL storage
  - ElastiCache handles Redis storage
  - Application logs → CloudWatch + S3 archive
  
Timeline: Parallel with database/cache migrations
```

---

### 1.3 Network Layer

#### VPC & Subnets
```
Classification: PERSISTENT (Infrastructure Foundation)
Deployment: Terraform IaC (Phase 3 Week 1)
```

**Characteristics**:
- ✅ Infrastructure as Code (recreatable)
- ✅ Immutable infrastructure pattern
- ⏳ Zero downtime when recreated (no data loss)
- ✅ Version controlled in git

**Lifecycle Policy**:
```
VPC: 1 per environment (prod/staging/dev)
Subnets:
  Public: 2 (app servers, NAT gateway)
  Private: 4 (database, cache, workers, reserved)
  
Route Tables:
  Public: Internet gateway route
  Private: NAT gateway route
  
Security Groups: 8 configured
  - PostgreSQL (RDS only)
  - Redis (RDS only)
  - ALB
  - App servers
  - Workers
  - SSH
  - Reserved (2)
```

**Disaster Recovery**:
- ✅ Complete IaC (can redeploy entire VPC in 5 minutes)
- ✅ Version controlled (git history)
- ✅ Tested in staging first
- ✅ Cross-region backup capability

---

#### SSL/TLS Certificates
```
Classification: PERSISTENT (Must be maintained)
Deployment: Terraform IaC + Let's Encrypt (Phase 3 Week 2)
```

**Characteristics**:
- ✅ Automated provisioning (Let's Encrypt)
- ✅ Automatic renewal (30 days before expiry)
- ⚠️ Domain continuity required (DNS validation)
- ✅ Zero-downtime renewal

**Lifecycle Policy**:
```
Certificate Duration: 90 days (Let's Encrypt standard)
Renewal Trigger: 30 days before expiry
Renewal Method: Route53 DNS-01 challenge
Renewal Window: Daily 01:00 UTC
Monitoring Threshold:
  Staging: 21 days (alert if not renewed)
  Production: 14 days (critical alert if not renewed)

Caddy Integration:
  - Automatic certificate reloading
  - No manual intervention required
  - Certificate file location: /etc/caddy/certificates/
```

**Disaster Recovery**:
- ✅ Re-provisioning automatic (Let's Encrypt renewal)
- ✅ ACM certificate backup in AWS
- ✅ Domain DNS records persistent (Route53)
- ✅ Old certificates retained (historical audit trail)

---

### 1.4 Application Layer

#### Application Code
```
Classification: EPHEMERAL (Code Container)
Deployment: Docker images (built fresh each deployment)
Source: Git repository (persistent)
```

**Characteristics**:
- ✅ Recreatable: Docker build from Dockerfile
- ✅ Version controlled in git
- ✅ Immutable containers (GitOps pattern)
- ✅ Zero state in container

**Lifecycle Policy**:
```
Build Artifact Retention: 14 most recent images
Image Scanning: Security scan on build
Image Signing: Signed with cosign
Tag Strategy:
  - Latest: Always latest main branch
  - Release: Semantic versioning (v1.0.0, etc.)
  - SHA: Commit hash for traceability
  
Build Frequency: Every commit (CI/CD)
Cleanup: Automated ECR lifecycle policy
```

**Disaster Recovery**:
- ✅ Source code in git (complete audit trail)
- ✅ Build reproducible from git commit
- ✅ Previous image versions available in ECR
- ✅ Rollback to previous image (5 min)

---

#### Configuration Files
```
Classification: PERSISTENT (Application Logic)
Deployment: Terraform templates + git versioning
Source: Git repository (persistent)
```

**Characteristics**:
- ✅ Version controlled (git)
- ✅ Environment-specific (dev/staging/prod tfvars)
- ⚠️ Secrets handled separately (AWS Secrets Manager, Phase 3 Week 3)
- ✅ Drift detection (Terraform state)

**Configuration Categories**:

```
Category 1: SSOT Configuration (PERSISTENT)
  Location: scripts/_common/config.env
  Type: Canonical environment variables
  Backup: Git repository
  Recovery: Git checkout + apply
  
Category 2: Application Config (PERSISTENT)
  Location: apps._shared.python.config.py (Phase 2C)
  Type: Type-safe configuration class
  Backup: Git repository
  Recovery: Git checkout + restart application
  
Category 3: Terraform Config (PERSISTENT)
  Location: terraform/environments/*/
  Type: Infrastructure as Code
  Backup: Git repository
  Recovery: terraform apply from git state
  
Category 4: Docker Compose (TRANSITIONAL)
  Location: docker-compose*.yml
  Type: Deployment orchestration
  Status: Being phased out (Phase 3 transitioning to K8s)
  Backup: Git repository
  Recovery: docker-compose up from git state
  
Category 5: Monitoring Config (PERSISTENT)
  Location: config/monitoring/ + Terraform
  Type: Dashboard + alert definitions
  Backup: Git + CloudWatch (AWS-managed)
  Recovery: Terraform reapply
```

---

#### Secrets & Credentials
```
Classification: PERSISTENT (CRITICAL)
Deployment: AWS Secrets Manager (Phase 3 Week 3)
Source: GSM (Google Secret Manager) for rotation
Status: Currently in .env files (being migrated)
```

**Characteristics**:
- ⚠️ NOT in git (security violation)
- ✅ Rotatable (automated every 90 days)
- ⚠️ High sensitivity (loss = security breach)
- ✅ Audit trail (CloudTrail)

**Current State** (To Be Fixed):
```
Locations (INSECURE - Fix in Phase 3 Week 3):
  1. .env files (not in git, but on file system)
  2. scripts/ci/.env (CI/CD variables)
  3. docker-compose environment sections
  
Plan (Phase 3 Week 3):
  1. Migrate to AWS Secrets Manager
  2. Remove from file system
  3. Rotate credentials
  4. Enable automatic rotation
  5. Audit all access (CloudTrail)
```

**Disaster Recovery**:
- ✅ AWS Secrets Manager versioning (automatically retains 3 versions)
- ✅ Secrets encrypted at rest (KMS)
- ✅ Audit trail (CloudTrail + Lambda logs)
- ✅ Cross-account secrets access (if needed)
- ⏳ Manual rotation procedure documented (Phase 3 Week 3)

---

#### Application Logs
```
Classification: EPHEMERAL (Aggregated → Persistent Archive)
Deployment: CloudWatch (Phase 3 Week 2+) + S3 Archive
Current: Docker logging driver + docker-compose volumes
```

**Characteristics**:
- ⚠️ Ephemeral: Data in CloudWatch (searchable)
- ✅ Archived to S3: Long-term retention (compliance)
- ⏳ Rotated weekly: Local storage cleanup
- ✅ Searchable: CloudWatch Insights

**Lifecycle Policy**:
```
Real-Time Logs (CloudWatch):
  Development: 1 week retention
  Staging: 2 weeks retention
  Production: 4 weeks retention
  Cost: $0.50/GB ingested

Archived Logs (S3):
  Development: 90 days, then delete
  Staging: 1 year, then delete
  Production: 7 years (compliance), then delete
  Cost: $0.023/GB/month + $0.0004/request
  
Local Logs (Docker volumes):
  app-logs/ volume: Rotated weekly
  Size limit: 50GB maximum
  Cleanup: Automated logrotate
```

**Disaster Recovery**:
- ✅ Long-term retention in S3
- ✅ Full audit trail (7 years production)
- ✅ CloudWatch Insights for analysis
- ✅ Log streaming to ELK (future option)

---

### 1.5 Monitoring & Observability

#### CloudWatch Dashboards
```
Classification: EPHEMERAL (Recreatable Configuration)
Deployment: Terraform IaC (Phase 3 Week 2+)
```

**Characteristics**:
- ✅ Recreatable: JSON template in Terraform
- ✅ Version controlled
- ⚠️ Loss: Only visualization loss (metrics still available)

**Lifecycle Policy**:
```
Dashboard Types:
  1. System Dashboards (created by Terraform)
     - RDS performance
     - ElastiCache metrics
     - Application health
     - Infrastructure status
  
  2. Custom Dashboards (created ad-hoc)
     - Temporary analysis
     - Ephemeral (not backed up)
  
Backup: Terraform state (terraform.tfstate)
Recovery: terraform apply (recreates dashboards)
Version Control: Dashboard JSON in git
```

---

#### CloudWatch Alarms
```
Classification: PERSISTENT (Alert Definitions)
Deployment: Terraform IaC (Phase 3 Week 2+)
```

**Characteristics**:
- ✅ Version controlled (Terraform)
- ✅ Recreatable from code
- ⚠️ Alert history: Not recreatable (lost on alarm deletion)

**Lifecycle Policy**:
```
Alarm Categories:
  1. Critical (production downtime risk)
     - Database connectivity
     - Cache failover
     - Certificate expiration
     - Application crashes
  
  2. Warning (performance degradation)
     - High CPU usage (>80%)
     - High memory (>85%)
     - Connection pool exhaustion
     - Slow queries (>5s)
  
  3. Info (operational awareness)
     - Backup completion
     - Deployment status
     - Log volume spikes
     - Cost anomalies

Retention: Alert history retained in SNS logs
Recovery: Terraform reapply (recreates alarm definitions)
Version Control: Alarm definitions in git
```

---

#### SNS Topics & Subscriptions
```
Classification: PERSISTENT (Notification Infrastructure)
Deployment: Terraform IaC (Phase 3 Week 2+)
```

**Characteristics**:
- ✅ Recreatable: Terraform definitions
- ✅ Version controlled
- ⚠️ Message history: Not retained (fire-and-forget)

**Lifecycle Policy**:
```
Topics Managed:
  1. ops-alerts: For all operational alerts
     Subscribers: Ops team Slack channel, email list
     
  2. deploy-status: For deployment notifications
     Subscribers: DevOps team, CI/CD logs
     
  3. certificate-expiry: For SSL/TLS alerts
     Subscribers: Ops team, security team
     
  4. billing-alerts: For cost monitoring
     Subscribers: Finance team, CFO

Backup: Topic configuration in Terraform
Recovery: terraform apply (recreates topics)
Version Control: SNS config in git
```

---

### 1.6 CI/CD & Automation

#### GitHub Actions Workflows
```
Classification: EPHEMERAL (Execution) + PERSISTENT (Definition)
Deployment: Git repository (.github/workflows/)
```

**Characteristics**:
- ✅ Workflow definitions: Version controlled (PERSISTENT)
- ⚠️ Workflow runs: Ephemeral (not archived)
- ✅ Workflow artifacts: Can be archived to S3
- ✅ Secrets: AWS Secrets Manager (Phase 3 Week 3)

**Lifecycle Policy**:
```
Workflow Definitions:
  - Branch protection rules
  - Status checks
  - Deployment gates
  - Review requirements
  
Execution Artifacts:
  - Build logs: Retained for 90 days
  - Test results: Archived to S3 (compliance)
  - Container images: 14 most recent versions
  - Deployment manifests: Archived to S3

Recovery:
  - Workflow re-execution from git commit
  - 5-minute RTO for failed deployments
```

---

#### Terraform State
```
Classification: PERSISTENT (CRITICAL)
Deployment: S3 remote state + DynamoDB locking
```

**Characteristics**:
- ⚠️ CRITICAL: Loss = infrastructure management nightmare
- ✅ S3 versioning enabled
- ✅ MFA delete protection
- ✅ Cross-region replication
- ✅ DynamoDB locking (prevents race conditions)

**Lifecycle Policy**:
```
S3 Backend:
  Bucket: terraform-state-{environment}
  Versioning: Enabled
  Server-side encryption: AES-256 (AWS-managed keys)
  Access logging: Enabled (track all access)
  MFA delete: Enabled (requires MFA to delete versions)
  Cross-region replication: Enabled (production only)
  
DynamoDB Lock Table:
  Name: terraform-locks
  Point-in-time recovery: Enabled
  Backups: AWS-managed (35-day retention)
  
Backup Strategy:
  - S3 versioning (unlimited versions)
  - Cross-region replication (production)
  - Manual snapshots before major changes
  - State file diff review before apply
```

**Disaster Recovery**:
- ✅ S3 versioning: Recover any previous state
- ✅ Cross-region replication: Recover from region failure
- ✅ Point-in-time DynamoDB recovery: 35 days
- ✅ Manual backup + git commit: Critical changes documented

**Restoration Procedure**:
```
If Terraform state corrupted:

1. Stop all terraform operations
   aws s3 ls s3://terraform-state-prod/

2. Identify good version
   aws s3api list-object-versions --bucket terraform-state-prod

3. Copy known-good version to current
   aws s3 cp s3://terraform-state-prod/prod.tfstate~{VERSION_ID} \
           s3://terraform-state-prod/prod.tfstate

4. Verify state integrity
   terraform state list

5. Proceed with caution (dry-run first)
   terraform plan
```

---

## 2. Resource Lifecycle Management

### 2.1 Creation Policies

| Resource Type | Automation | Approval | Monitoring |
|---------------|-----------|----------|-----------|
| **Persistent** | 50% (Terraform IaC) | 2-person review | Real-time alerts |
| **Ephemeral** | 90% (Automated CI/CD) | Automated | Log-based |
| **Hybrid** | 70% (Managed service) | 1-person review | Real-time monitoring |

### 2.2 Update Policies

```
For PERSISTENT Resources:
  ✓ Blue-green deployments
  ✓ Database migration validation
  ✓ Backup before major changes
  ✓ Rollback procedure ready
  ✓ Staging test first
  ✓ Change log in git

For EPHEMERAL Resources:
  ✓ Recreate from code (immutable)
  ✓ Minimal downtime (rolling deployment)
  ✓ Automated rollback capability
  ✓ No manual changes to containers

For HYBRID Resources:
  ✓ Evaluate persistent portions
  ✓ Plan ephemeral cleanup
  ✓ Test in staging first
  ✓ Fallback strategy ready
```

### 2.3 Deletion Policies

```
Deletion Protection (Enabled):
  - RDS instances (production)
  - ElastiCache clusters (production)
  - S3 buckets with state files
  - Route53 zones
  - IAM roles with production access

Deletion Workflow:
  1. Removal of deletion_protection = true
  2. 2-person review + approval
  3. Backup verification
  4. 48-hour notice to team
  5. Execute deletion
  6. Verify recovery capability post-deletion
```

---

## 3. Disaster Recovery by Resource Type

### 3.1 Database Recovery Scenarios

```
SCENARIO: PostgreSQL corruption (1 table affected)
  RTO: 2 hours
  RPO: 1 minute (point-in-time recovery)
  Action:
    1. Restore RDS from point-in-time snapshot
    2. Validate restored database
    3. Application cutover (environment variable update)
    4. Verify data integrity
    5. Schedule original cleanup (2 weeks)

SCENARIO: Redis cluster failure (all 3 nodes down)
  RTO: 5 minutes
  RPO: 0 minutes (automatic failover + AOF)
  Action:
    1. Automatic failover in ElastiCache
    2. New leader elected
    3. Sessions restored from AOF
    4. Application reconnects automatically
    5. Monitor cluster rebuild (10-15 min)

SCENARIO: Regional failure (all resources gone)
  RTO: 4 hours
  RPO: Depends on last backup (24 hours max)
  Action:
    1. Redeploy VPC in alternate region (10 min)
    2. Restore RDS from snapshot (45 min)
    3. Restore ElastiCache from snapshot (30 min)
    4. Update DNS (5 min, cache 300s)
    5. Application reconnection (5 min)
    6. Validation (30 min)
    7. Final switchover (10 min)
```

### 3.2 Backup & Recovery Priority Matrix

| Resource | Ephemeral | Backup Required | RTO | RPO |
|----------|-----------|-----------------|-----|-----|
| PostgreSQL | No | ✅ Yes | 2h | 1m |
| Redis | Hybrid | ✅ Yes (selective) | 5m | 0m |
| Redpanda | Hybrid | ✅ Yes | 30m | 1h |
| Qdrant | Hybrid | ✅ Yes | 4h | 2h |
| App Code | Yes | No* | 10m | N/A |
| Config | No | ✅ Yes | 30m | 5m |
| Secrets | No | ✅ Yes | 15m | 0m |
| Certificates | No | Partial** | 1h | N/A |

\* App code recreatable from git  
\** Certificate renewal automatic, historical audit trail

### 3.3 Recovery Time Objectives (RTO)

```
TIER 1 (< 5 minutes):
  ✓ ElastiCache cluster failure (automatic)
  ✓ Application container crash (auto-restart)
  ✓ Certificate validation failure (retry mechanism)

TIER 2 (5-30 minutes):
  ✓ Single RDS node failure (automatic failover)
  ✓ Application deployment rollback (5-10 min)
  ✓ Configuration update revert (10-15 min)

TIER 3 (30 min - 2 hours):
  ✓ Database corruption (point-in-time restore)
  ✓ Secrets compromise (credential rotation)
  ✓ Major configuration revert

TIER 4 (2-4 hours):
  ✓ Regional failure (alternate region deployment)
  ✓ Qdrant vector database loss (re-indexing)
  ✓ Multiple service failure cascade
```

---

## 4. Cost Optimization by Resource Classification

### 4.1 Persistent Resources (Higher Cost = Expected)

```
PostgreSQL RDS:
  Cost: High (managed service, always-on, backup storage)
  Justification: Data persistence essential
  Optimization: Right-size instance class per environment
  
ElastiCache Redis:
  Cost: High (multi-node in production for HA)
  Justification: Performance + availability
  Optimization: Use cluster mode, adjust reserved capacity
  
S3 Backup Storage:
  Cost: Medium (long-term retention)
  Justification: Compliance + disaster recovery
  Optimization: Transition to Glacier after 1 year
```

### 4.2 Ephemeral Resources (Lower Cost = OK to Discard)

```
Application Logs:
  Cost: Medium (CloudWatch ingestion + storage)
  Justification: Ephemeral data can be archived
  Optimization: Rotate to S3 Glacier after 90 days
  
Build Artifacts:
  Cost: Low (short retention, automated cleanup)
  Justification: Ephemeral, recreatable from git
  Optimization: Automated ECR cleanup policy
  
Temporary Volumes:
  Cost: Low (transient, weekly cleanup)
  Justification: Ephemeral, not needed long-term
  Optimization: Size appropriately, scheduled purge
```

### 4.3 Cost Allocation by Classification

```
Budget Allocation (Annual):
  Persistent Infrastructure: 60% ($25,000+)
    - RDS databases
    - ElastiCache clusters
    - S3 backup storage
    - Backup retention
  
  Ephemeral/Operational: 25% ($10,000)
    - CloudWatch logs
    - Build artifacts
    - Temporary storage
    - Data transfer
  
  Security/Compliance: 10% ($4,000)
    - Secrets Manager
    - KMS encryption
    - CloudTrail
    - Security scanning
  
  Reserve/Buffer: 5% ($2,000)
    - Unplanned costs
    - Testing resources
    - Temporary workloads
```

---

## 5. Transition Timeline & Implementation

### 5.1 Phase 3 Week 2 (Current - April 28 - May 11)

```
✅ Database IaC: RDS + ElastiCache deployment (COMPLETE)
✅ SSL/TLS ACME: Certificate automation (COMPLETE)
⏳ Resource Classification: This document (IN PROGRESS)
⏳ Tier 2 App Migrations: 7 application config consolidation

Actions This Week:
  1. Deploy database module to staging
  2. Run Alembic migrations
  3. Deploy SSL/TLS to staging
  4. Validate certificate renewal flow
  5. Create resource classification document (THIS)
  6. Plan Tier 2 app migration batch
```

### 5.2 Phase 3 Week 3 (May 12 - May 18)

```
Production Database Deployment:
  1. Deploy RDS to production
  2. Migrate data from Docker → RDS
  3. Update application endpoints
  4. Verify 48 hours in production
  5. Docker Compose postgres shutdown

Production SSL/TLS Deployment:
  1. Deploy ACME to production
  2. Provision production certificates
  3. Verify certificate renewal workflow
  4. Monitor first renewal cycle

Begin Tier 2 App Migrations:
  1. Start batch 1: activity_feed, agent-runtime
  2. Run validation tests
  3. Commit to git with comprehensive messaging
  4. Proceed to batch 2
```

### 5.3 Phase 3 Week 4 (May 19 - May 25)

```
Tier 2 App Migrations (Continued):
  1. Batch 2: edge_agent, api_gateway
  2. Batch 3: orchestrator, dashboard
  3. Batch 4: event_processor

Secrets Management Migration:
  1. Create AWS Secrets Manager vaults
  2. Migrate .env secrets to Secrets Manager
  3. Update all applications for credential retrieval
  4. Enable automatic credential rotation
  5. Remove .env files from file system

Monitoring & Observability:
  1. CloudWatch dashboards for all resources
  2. Alert definitions for each resource class
  3. SNS subscriptions for ops team
  4. Log streaming setup (CloudWatch → S3 archive)
```

### 5.4 Phase 4+ (June and Beyond)

```
Kubernetes Migration (Phase 4):
  1. Migrate from Docker Compose to EKS
  2. Stateless application deployment
  3. Stateful resource (databases) remain on RDS/ElastiCache

Advanced Monitoring (Phase 4):
  1. Distributed tracing (X-Ray)
  2. Application performance monitoring
  3. Custom metrics
  4. Machine learning anomaly detection

Disaster Recovery Testing (Phase 4+):
  1. Annual DR drills
  2. Regional failover testing
  3. Backup restoration validation
  4. RTO/RPO verification
```

---

## 6. Resource-by-Resource Recovery Procedures

### 6.1 PostgreSQL RDS Failure Recovery

```bash
# STEP 1: Identify failure
aws rds describe-db-instances --db-instance-identifier prod-postgres-primary \
  --query 'DBInstances[0].[DBInstanceStatus, DBInstanceIdentifier]'

# STEP 2: Create point-in-time restore
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier prod-postgres-primary \
  --target-db-instance-identifier prod-postgres-recovery-$(date +%s) \
  --restore-time 2026-04-28T12:00:00Z \
  --db-instance-class db.t4g.xlarge

# STEP 3: Wait for restore completion (30-45 min)
aws rds wait db-instance-available \
  --db-instance-identifier prod-postgres-recovery-$(date +%s)

# STEP 4: Promote to primary
# Update POSTGRES_HOST environment variable
# Verify connectivity from application
# Run health checks
curl https://app.example.com/health

# STEP 5: Cleanup old instance
# After 48-hour verification:
aws rds delete-db-instance \
  --db-instance-identifier prod-postgres-primary \
  --skip-final-snapshot
```

### 6.2 ElastiCache Cluster Failure Recovery

```bash
# STEP 1: Check cluster status
aws elasticache describe-replication-groups \
  --replication-group-id prod-redis-primary \
  --query 'ReplicationGroups[0].Status'

# STEP 2: Automatic failover (if Multi-AZ enabled)
# No action needed - automatic failover happens
# New primary elected, replicas promoted

# STEP 3: Verify cluster state
aws elasticache describe-replication-groups \
  --replication-group-id prod-redis-primary \
  --query 'ReplicationGroups[0].MemberClusters'

# STEP 4: Monitor cluster rebuild (10-15 min)
# Verify AOF persistence status
aws elasticache describe-cache-parameters \
  --parameter-group-name prod-redis-params \
  --query 'Parameters[?ParameterName==`appendonly`]'

# STEP 5: Application recovery (automatic)
# Redis client reconnects to new primary
# Sessions restored from AOF
# No manual action needed
```

### 6.3 Certificate Expiration Recovery

```bash
# STEP 1: Monitor certificate status
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789:certificate/abc123 \
  --query 'Certificate.[DomainName, NotAfter, CertificateStatus]'

# STEP 2: Alert triggered (14-21 days before expiry)
# EventBridge triggers Lambda renewal automatically

# STEP 3: Renewal process
# Lambda executes: Route53 validation → Certificate renewal → Caddy reload
aws logs tail /aws/lambda/certificate-renewal --follow

# STEP 4: Verify renewal
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789:certificate/abc123 \
  --query 'Certificate.NotAfter'

# STEP 5: If automatic renewal fails
# Manual renewal (requires DNS access):
aws acm request-certificate \
  --domain-name example.com \
  --validation-method DNS \
  --subject-alternative-names "*.example.com" "app.example.com"
```

---

## 7. Resource Dependency Map

```
DEPENDENCY CHAIN (Critical Path):

1. VPC (Foundation)
   ↓
2. Subnets + Route Tables
   ↓
3. Security Groups
   ├→ RDS (PostgreSQL)
   │  ├→ Application Code
   │  └→ Alembic Migrations
   │
   ├→ ElastiCache (Redis)
   │  ├→ Session Data
   │  └→ Cache Layer
   │
   └→ Route53 (DNS)
      └→ ACM Certificates
         └→ Caddy (Reverse Proxy)
            └→ Applications

CIRCULAR DEPENDENCIES (Watch Out):
  ❌ Application → Database → IAM Role → Application
     SOLUTION: Create IAM role BEFORE application deployment
  
  ❌ Certificate → Caddy → Certificate Renewal
     SOLUTION: Caddy reloads automatically (no circular)

INDEPENDENT RESOURCES (Can Fail Independently):
  ✓ CloudWatch Dashboards (visualization only)
  ✓ SNS Topics (notification system)
  ✓ S3 Backup Storage (archive only)
```

---

## 8. Resource Health Check Procedures

### 8.1 PostgreSQL Health Check

```bash
#!/bin/bash

# Connection test
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT 1" && echo "✓ PostgreSQL connected"

# Replication lag check
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as replication_lag_seconds;"

# Backup status check
aws rds describe-db-backups \
  --db-instance-identifier prod-postgres-primary \
  --query 'DBBackups[0].[DBInstanceIdentifier, BackupCreateTime, Status]'

# Disk usage check
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size DESC LIMIT 5;"
```

### 8.2 ElastiCache Health Check

```bash
#!/bin/bash

# Cluster status
aws elasticache describe-replication-groups \
  --replication-group-id prod-redis-primary \
  --query 'ReplicationGroups[0].[Status, AutomaticFailover]'

# Eviction rate (cache thrashing check)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name Evictions \
  --dimensions Name=ReplicationGroupId,Value=prod-redis-primary \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Memory usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=ReplicationGroupId,Value=prod-redis-primary \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### 8.3 Certificate Health Check

```bash
#!/bin/bash

# Certificate expiration check
aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --query 'Certificate.[DomainName, NotAfter, CertificateStatus]'

# Days until expiration
EXPIRY=$(aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --query 'Certificate.NotAfter' \
  --output text)
DAYS_LEFT=$(( ($(date -d "$EXPIRY" +%s) - $(date +%s)) / 86400 ))
echo "Days until expiration: $DAYS_LEFT"

# Recent renewals
aws logs tail /aws/lambda/certificate-renewal \
  --since 1w --format short | head -20

# DNS validation records
aws route53 list-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --query "ResourceRecordSets[?Name=='_acme-challenge.*']"
```

---

## 9. Appendix: Quick Reference

### 9.1 Classification Quick Lookup

| Resource | Class | Backup | Recovery | Cost |
|----------|-------|--------|----------|------|
| RDS PostgreSQL | Persistent | Automated | Hours | High |
| ElastiCache Redis | Hybrid | Automated | Minutes | High |
| Application Logs | Ephemeral | Archive | Days | Medium |
| Config Files | Persistent | Git | Minutes | Low |
| Secrets | Persistent | Managed | Minutes | Medium |
| SSL/TLS Certs | Persistent | Automatic | Hour | Low |
| App Code | Ephemeral | Git | Minutes | Low |
| Terraform State | Persistent | Versioned | Hours | Medium |

### 9.2 Disaster Recovery Decision Tree

```
RESOURCE LOST?
├─ Application Container
│  └─ Can recreate from Docker image? → YES → Restart/Redeploy
│
├─ Database (PostgreSQL)
│  └─ Corrupted or lost? → Restore from RDS snapshot (2 hours)
│
├─ Cache (Redis)
│  └─ Node failure? → Automatic failover (5 minutes)
│
├─ Certificate
│  └─ Expired? → Automatic renewal via Let's Encrypt
│
├─ Configuration
│  └─ Lost from file system? → Restore from git checkout
│
├─ Secrets
│  └─ Compromised? → Rotate via AWS Secrets Manager
│
└─ Entire Region
   └─ Redeploy VPC + restore from snapshots (4 hours)
```

### 9.3 Backup Frequency Summary

| Resource | Frequency | Retention | Method |
|----------|-----------|-----------|--------|
| PostgreSQL | Daily | 30 days | RDS automatic |
| Redis | Hourly (AOF) | 5 snapshots | ElastiCache |
| Configuration | On commit | ∞ | Git |
| Terraform state | Continuous | Unlimited | S3 versioning |
| Application logs | Real-time | 4 weeks | CloudWatch + S3 |
| Secrets | On rotation | 3 versions | AWS Secrets Mgr |
| Certificates | N/A | Automatic | Let's Encrypt |

---

## 10. Implementation Checklist

- [ ] **Week of May 5**: Deploy database + SSL/TLS to staging
- [ ] **Week of May 5**: Validate all persistent resources have backups
- [ ] **Week of May 5**: Configure CloudWatch monitoring for all resources
- [ ] **Week of May 12**: Production database + SSL/TLS deployment
- [ ] **Week of May 12**: Enable Secrets Manager (remove .env files)
- [ ] **Week of May 12**: Configure cross-region backup replication
- [ ] **Week of May 19**: Run first disaster recovery drill
- [ ] **Week of May 19**: Document all recovery procedures (scripts ready)
- [ ] **Week of June 2**: Verify recovery procedures work (full DR test)
- [ ] **Monthly**: Review backup integrity (restore test)
- [ ] **Quarterly**: Full disaster recovery drill with team
- [ ] **Annually**: Update RTO/RPO targets and recovery procedures

---

## Summary

This resource classification framework provides:

✅ **Clear ownership** of which resources must be backed up vs recreated  
✅ **Recovery procedures** with RTO/RPO targets for each resource class  
✅ **Cost transparency** showing why persistent resources cost more  
✅ **Implementation timeline** aligned with Phase 3 schedule  
✅ **Health check procedures** for ongoing monitoring  
✅ **Disaster recovery** decision trees and runbooks  

**Next Step**: Phase 3 Week 3 (May 12-18) will execute production deployment of database + SSL/TLS modules and begin Tier 2 app migrations.
