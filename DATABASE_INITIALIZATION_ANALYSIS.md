# Database Initialization Analysis Report

**Date**: April 28, 2026  
**Scope**: Code-Server ElevatedIQ DevOS Stack  
**Focus**: Actionable discovery for Terraform IaC migration  
**Thoroughness**: Medium (comprehensive core patterns identified)

---

## Executive Summary

The codebase currently initializes databases through a multi-layered approach:
1. **Docker Compose** - Primary orchestration for PostgreSQL, Redis, Redpanda, Qdrant
2. **Alembic Migrations** - Python-based schema versioning for PostgreSQL
3. **Environment Variables** - Configuration-driven initialization
4. **SQLAlchemy ORM** - Application-layer database initialization

**Key Finding**: Terraform has minimal database infrastructure code. The storage module exists but doesn't provision database services. This is a significant opportunity for IaC consolidation.

---

## 1. Current Database Services Inventory

### 1.1 PostgreSQL (Primary OLTP Database)

| Property | Value |
|----------|-------|
| **Image** | postgres:16-alpine@sha256:4e6e670bb069649261c9c18031f0aded7bb249a5b6664ddec29c013a89310d50 |
| **Container** | code-server-postgres |
| **Port** | 5432 |
| **User** | 999:999 (non-root, security-hardened) |
| **Volume** | postgres_data:/var/lib/postgresql/data |
| **Resource Limits** | CPU: 2.0, Memory: 4GB |
| **Reservations** | CPU: 1.0, Memory: 2GB |
| **Health Check** | `pg_isready -U ${DB_USER}` (30s interval) |
| **Restart Policy** | unless-stopped |
| **Networks** | services, database (separate network for isolation) |

**Initialization Environment Variables**:
```yaml
POSTGRES_DB: ${DB_NAME}
POSTGRES_USER: ${DB_USER}
POSTGRES_PASSWORD: ${DB_PASSWORD}
POSTGRES_INITDB_ARGS: "--encoding=UTF8 -c max_wal_senders=10 -c wal_level=replica"
```

**Database Consumers**:
- reputation-engine (port 8002)
- execution-scheduler (port 8080)
- auth-server
- edge-agent

---

### 1.2 Redis (Cache & Session Store)

| Property | Value |
|----------|-------|
| **Image** | redis:7-alpine@sha256:7aec734b2bb298a1d769fd8729f13b8514a41bf90fcdd1f38ec52267fbaa8ee6 |
| **Container** | code-server-redis |
| **Port** | 6379 |
| **User** | 999:999 (non-root) |
| **Command** | `redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}` |
| **Volume** | redis_data:/data |
| **Resource Limits** | CPU: 2.0, Memory: 4GB |
| **Reservations** | CPU: 1.0, Memory: 2GB |
| **Health Check** | `redis-cli --raw incr ping` (30s interval) |
| **Restart Policy** | unless-stopped |
| **Networks** | services |

**Redis Configuration** (from .env.cluster):
```yaml
REDIS_MAXMEMORY: 6gb
REDIS_MAXMEMORY_POLICY: allkeys-lru
REDIS_APPENDONLY: yes
REDIS_PASSWORD: redis_secure_2026
```

**Sentinel Support**:
```
redis-sentinel-1:26379,26380,26381  # For high availability
```

---

### 1.3 Redpanda (Event Streaming / Kafka Alternative)

| Property | Value |
|----------|-------|
| **Image** | docker.redpanda.com/redpandadata/redpanda:v26.1.6 |
| **Container** | code-server-redpanda |
| **Kafka Port** | 9092 (OUTSIDE), 29092 (PLAINTEXT) |
| **Schema Registry** | 8081 |
| **Pandaproxy** | 8082 |
| **RPC Port** | 33145 |
| **Volume** | redpanda_data:/var/lib/redpanda/data |
| **Health Check** | `curl -fsS http://localhost:9644/v1/status/ready` |

**Event Streaming Consumers**:
- execution-scheduler
- activity-feed
- reputation-engine

---

### 1.4 Qdrant (Vector Database for AI/Embeddings)

| Property | Value |
|----------|-------|
| **Image** | qdrant/qdrant:v1.7.0 |
| **Container** | code-server-qdrant |
| **Port** | 6333, 6334 |
| **User** | 1000:1000 |
| **Volumes** | /qdrant/storage, /qdrant/storage/snapshots, /qdrant/storage/wal |
| **Resource Limits** | CPU: 2.0, Memory: 2GB |
| **Reservations** | CPU: 1.0, Memory: 1GB |

**Consumers**:
- memory-engine (port 8001)
- AI/ML services (profile: ai)

---

## 2. Database Initialization Methods

### 2.1 Method A: Alembic Migrations (Python ORM)

**Framework**: Python SQLAlchemy + Alembic  
**Location**: `/migrations/versions/` (root level) + per-app migrations

**Migration Files**:

| File | Schema | Issue | Status |
|------|--------|-------|--------|
| `001_oauth2_schema.py` | OAuth2 Authorization | #1545 Enterprise SSO | OAuth providers, auth codes, access/refresh tokens |
| `002_user_management_schema.py` | User Models | #1345 Week 2 | users, user_profiles, email_change_requests, user_activity_logs |
| `003_team_organization_schema.py` | Team Organization | TBD | Team management schema |
| `004_advanced_authentication_schema.py` | Advanced Auth | TBD | Multi-factor auth, sessions |
| `005_api_gateway_schema.py` | API Gateway | TBD | API key management, quotas |
| `apps/auth-server/migrations/optimize_database_indexes.py` | Performance | Week 5 Phase 5.2.1 | Strategic indexes on users, teams, permissions |

**Alembic Usage**:
```bash
alembic upgrade head          # Apply all pending migrations
alembic upgrade +1            # Apply next migration
alembic downgrade -1          # Rollback last migration
alembic revision --autogenerate -m "description"  # Generate new migration
```

**Package Versions**:
- SQLAlchemy: 2.0.23 - 2.0.25
- Alembic: 1.12.1 - 1.13.0

**Apps Using Alembic**:
- auth-server (requirements.txt: sqlalchemy==2.0.23, alembic==1.13.0)
- edge-agent (sqlalchemy==2.0.25, alembic==1.13.0)
- reputation_engine (sqlalchemy==2.0.25)
- execution-scheduler (sqlalchemy==2.0.25)

---

### 2.2 Method B: SQLAlchemy ORM Base Initialization

**Location**: `/scripts/ops/init-reputation-db.py`

```python
import sys
import os
sys.path.append(os.path.join(os.getcwd(), 'apps', 'reputation-engine'))
from models import Base
from sqlalchemy import create_engine

def init_local_db():
    database_url = 'sqlite:///reputation_engine.db'
    engine = create_engine(database_url)
    Base.metadata.create_all(bind=engine)
    print(f"SQLite database created successfully at {os.path.abspath('reputation_engine.db')}")
```

**Purpose**: Local SQLite database initialization for testing/development  
**Database**: reputation_engine.db (in repository root)

---

### 2.3 Method C: PostgreSQL Native Initialization

**Trigger**: Docker container startup  
**Configuration**: Via `POSTGRES_INITDB_ARGS`

```yaml
POSTGRES_INITDB_ARGS: "--encoding=UTF8 -c max_wal_senders=10 -c wal_level=replica"
```

**Settings Explanation**:
- `--encoding=UTF8`: Sets database encoding
- `max_wal_senders=10`: Enables up to 10 streaming replication connections
- `wal_level=replica`: Enables WAL archiving for replication/recovery

**Health Verification**:
```bash
pg_isready -U ${DB_USER}  # Checks PostgreSQL readiness
```

---

## 3. Environment Variables for Database Setup

### 3.1 Cluster Deployment (.env.cluster)

```env
# PostgreSQL Configuration
DB_NAME=kushnir_db
DB_USER=postgres
DB_PASSWORD=k8s_secure_postgres_2026
POSTGRES_INITDB_ARGS=-c max_wal_senders=10 -c wal_level=replica

# Redis Configuration
REDIS_PASSWORD=redis_secure_2026
REDIS_MAXMEMORY=6gb
REDIS_MAXMEMORY_POLICY=allkeys-lru
REDIS_APPENDONLY=yes
```

### 3.2 Development Deployment (.env.deployment)

```env
DB_USER=postgres
DB_PASSWORD=postgres-dev-password
DB_NAME=devos
REDIS_PASSWORD=redis-dev-password
```

### 3.3 Environment Variable Schema (.env.schema.json)

```json
{
  "DB_USER": {
    "category": "database",
    "type": "string",
    "required": false,
    "default": "postgres",
    "description": "PostgreSQL user",
    "usage": ["DATABASE_URL", "Docker Compose"]
  },
  "DB_PASSWORD": {
    "category": "database",
    "type": "string",
    "required": false,
    "sensitive": true,
    "description": "PostgreSQL password",
    "usage": ["DATABASE_URL", "Docker Compose"]
  },
  "DB_NAME": {
    "category": "database",
    "type": "string",
    "required": false,
    "description": "Database name",
    "usage": ["DATABASE_URL"]
  },
  "DATABASE_URL": {
    "category": "database",
    "type": "string",
    "computed": "postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}",
    "description": "PostgreSQL connection string"
  },
  "REDIS_PASSWORD": {
    "category": "database",
    "type": "string",
    "required": false,
    "sensitive": true,
    "description": "Redis password"
  }
}
```

---

## 4. Migration File Locations

| Category | Path | Files |
|----------|------|-------|
| **Core Migrations** | `/migrations/versions/` | 001-005_*.py (5 files) |
| **Auth Server** | `/apps/auth-server/migrations/` | optimize_database_indexes.py |
| **Backup Scripts** | `/scripts/ops/` | init-reputation-db.py |
| **Schema Templates** | `/schemas/` | TBD (need to verify) |

### 4.1 Sample Migration Structure (002_user_management_schema.py)

**Tables Created**:

1. **users**
   - PK: id (UUID)
   - Fields: email, name, avatar_url, status, email_verified, bio, company, location, locale, timezone, preferences
   - Constraints: unique(email)
   - Indexes: email, (email, email_verified), created_at

2. **user_profiles**
   - PK: id (UUID)
   - FK: user_id → users.id
   - Fields: display_name, bio, avatar_url, job_title, company, country, timezone, social_links
   - Constraints: unique(user_id)

3. **email_change_requests**
   - PK: id (UUID)
   - FK: user_id → users.id
   - Fields: old_email, new_email, verification_token, is_verified, expires_at
   - Indexes: user_id, verification_token

4. **user_activity_logs**
   - PK: id (UUID)
   - FK: user_id → users.id
   - Fields: activity_type, activity_description, status, ip_address

---

## 5. Database Service Dependencies

### 5.1 Service to Database Mapping

| Service | Database | Connection Method | Port |
|---------|----------|-------------------|------|
| **reputation-engine** | PostgreSQL | DATABASE_URL env var | 5432 |
| **execution-scheduler** | PostgreSQL | DATABASE_URL env var | 5432 |
| **auth-server** | PostgreSQL | Alembic + SQLAlchemy | 5432 |
| **edge-agent** | PostgreSQL | Alembic + SQLAlchemy | 5432 |
| **activity-feed** | Redpanda | KAFKA_BROKER env var | 9092 |
| **execution-scheduler** | Redpanda | KAFKA_BROKER env var | 9092 |
| **memory-engine** | Qdrant | QDRANT_HOST env var | 6333 |
| **multimodal-ai** | Ollama (embeddings) | OLLAMA_BASE_URL | 11434 |

### 5.2 Docker Compose Depends_on Declarations

```yaml
reputation-engine:
  depends_on:
    postgres:
      condition: service_healthy
    redpanda:
      condition: service_healthy
    opa:
      condition: service_healthy

execution-scheduler:
  depends_on:
    postgres:
      condition: service_healthy
    redpanda:
      condition: service_healthy
```

---

## 6. Terraform Current State

### 6.1 Existing Database-Related Terraform

**Location**: `terraform/modules/storage/`

**Current Capabilities**:
- Volume sizing for PostgreSQL (`postgres_volume_size_gb` variable)
- Volume sizing for Redis
- Backup path configuration
- Mount path templating

**Current Limitations**:
- No database service provisioning
- No credentials management
- No network security policies
- No RDS/managed database support
- No backup automation

### 6.2 Example: storage/variables.tf

```hcl
variable "postgres_volume_size_gb" {
  description = "PostgreSQL data volume size (GB)"
  type        = number
  default     = 100
}
```

### 6.3 Network References in Terraform

**From core/main.tf**:
```hcl
internal_services = [
  "execution-scheduler:8080",
  "opa-service:8181",
  "prompt-gateway:8000",
  "postgres-db:5432",
  "redis-cache:6379",
  "redpanda-broker:9092"
]
```

---

## 7. SQL Schema Overview

### 7.1 Core Schema Objects (from Alembic migrations)

**OAuth2 Schema** (001_oauth2_schema.py):
- `oauth_providers` - OAuth configuration (Google, GitHub, etc.)
- `oauth_authorization_codes` - Authorization code flow
- `oauth_access_tokens` - Token storage
- `oauth_refresh_tokens` - Refresh token storage

**User Schema** (002_user_management_schema.py):
- `users` - Core user accounts
- `user_profiles` - Extended user information
- `email_change_requests` - Email verification workflow
- `user_activity_logs` - Audit/security logging

**Team Schema** (003_team_organization_schema.py):
- Inferred: teams, team_members, team_roles

**Authentication Schema** (004_advanced_authentication_schema.py):
- Inferred: MFA settings, session tokens, device management

**API Gateway Schema** (005_api_gateway_schema.py):
- Inferred: API keys, quotas, rate limits

### 7.2 Performance Indexes (from optimize_database_indexes.py)

```sql
-- Users indexes
CREATE INDEX ix_users_team_id ON users(team_id);
CREATE INDEX ix_users_created_at ON users(created_at);
CREATE INDEX ix_users_is_active ON users(is_active);
CREATE INDEX ix_users_team_id_is_active ON users(team_id, is_active);
CREATE INDEX ix_users_created_at_team_id ON users(created_at, team_id);

-- Teams indexes
CREATE INDEX ix_teams_organization_id ON teams(organization_id);
CREATE INDEX ix_teams_created_at ON teams(created_at);
CREATE INDEX ix_teams_organization_id_created_at ON teams(organization_id, created_at);

-- Permission indexes
CREATE INDEX ix_permissions_user_id ON permissions(user_id);
CREATE INDEX ix_permissions_role_id ON permissions(role_id);
CREATE INDEX ix_permissions_team_id ON permissions(team_id);
```

---

## 8. Database Storage & Backup Paths

### 8.1 Volume Configuration (Docker Compose)

| Service | Volume Name | Mount Path | Backup Path |
|---------|-------------|-----------|------------|
| **PostgreSQL** | postgres_data | /var/lib/postgresql/data | ${storage_mount_path}/backups/postgresql |
| **Redis** | redis_data | /data | TBD |
| **Redpanda** | redpanda_data | /var/lib/redpanda/data | TBD |
| **Qdrant** | qdrant_data | /qdrant/storage | TBD |

### 8.2 Terraform Storage Module Configuration

**Path**: `terraform/modules/storage/main.tf`

```hcl
postgres_volume_gb    = var.postgres_volume_size_gb
postgres_data         = "${var.storage_mount_path}/postgresql/data"
redis_data            = "${var.storage_mount_path}/redis/data"
postgres_backup_path  = "${var.storage_mount_path}/backups/postgresql"
```

---

## 9. Key Findings & IaC Migration Opportunities

### 9.1 ✅ Strengths in Current Setup

1. **Declarative Migrations**: Alembic provides version control for schema changes
2. **Environment-Driven Config**: All credentials/settings via environment variables
3. **Health Checks**: Built-in readiness probes for all services
4. **Network Isolation**: Separate "database" network for PostgreSQL
5. **Non-Root Users**: Security hardened (postgres:999:999, redis:999:999)
6. **Resource Limits**: CPU/memory reservations defined
7. **Restart Policies**: Services configured for resilience

### 9.2 🔧 Gaps for Terraform IaC Migration

| Gap | Current State | Terraform Opportunity |
|-----|---------------|----------------------|
| **Database Provisioning** | Docker Compose only | RDS provisioning, instance sizing |
| **Secrets Management** | Environment files | AWS Secrets Manager, HashiCorp Vault |
| **User Privileges** | PostgreSQL defaults | Terraform-managed database users, roles |
| **Backup Automation** | Manual volumes | AWS Backup, automated snapshots |
| **Replication Setup** | WAL config only | Multi-AZ RDS, read replicas |
| **Monitoring** | CloudWatch/Prometheus | Terraform-managed alarms, dashboards |
| **Network Security** | Docker networks | Security groups, NACLs, encryption in transit |
| **Parameter Groups** | Hardcoded INITDB_ARGS | Parameter groups (RDS-compatible) |
| **Failover** | Manual | Auto-failover policies |

### 9.3 🎯 Recommended Terraform IaC Patterns to Build

**Phase 1 - Core Database Resources**:
```
✓ aws_db_instance (PostgreSQL)
✓ aws_elasticache_cluster (Redis)
✓ aws_security_group (database access)
✓ aws_db_parameter_group (PostgreSQL settings)
```

**Phase 2 - Secrets & Configuration**:
```
✓ aws_secretsmanager_secret (credentials)
✓ aws_secretsmanager_secret_version (rotation)
✓ terraform variables for environment-specific settings
✓ outputs for connection strings
```

**Phase 3 - Backup & Monitoring**:
```
✓ aws_backup_plan (automated snapshots)
✓ aws_cloudwatch_metric_alarm (database health)
✓ aws_log_group (slow queries, errors)
```

---

## 10. Implementation Roadmap for Terraform IaC

### Phase 1: Foundation (Week 1)
- [ ] Create `terraform/modules/database/` directory
- [ ] Implement `aws_db_instance` for PostgreSQL
- [ ] Implement `aws_elasticache_cluster` for Redis
- [ ] Create security groups for database access
- [ ] Add variables for instance sizing, storage, multi-AZ

### Phase 2: Configuration Management (Week 2)
- [ ] Integrate AWS Secrets Manager for credentials
- [ ] Create `aws_db_parameter_group` with Alembic-compatible settings
- [ ] Add environment-specific terraform.tfvars
- [ ] Document migration path from docker-compose

### Phase 3: Operations (Week 3)
- [ ] Automated backup policies
- [ ] CloudWatch alarms for replication lag, disk space
- [ ] Connection pooling configuration (PgBouncer)
- [ ] Read replica provisioning

### Phase 4: Validation & Cutover (Week 4)
- [ ] Test Alembic migration compatibility
- [ ] Verify connection strings and credentials
- [ ] Performance testing (docker-compose vs RDS)
- [ ] Rollback procedures

---

## Appendix A: Quick Reference

### Docker Compose Database Services
```bash
# Start all databases
docker-compose up -d postgres redis redpanda qdrant

# Check service health
docker-compose ps
docker-compose logs postgres

# Access PostgreSQL
docker-compose exec postgres psql -U postgres -d kushnir_db

# Access Redis
docker-compose exec redis redis-cli

# Run Alembic migrations
docker-compose exec reputation-engine alembic upgrade head
```

### Alembic Commands
```bash
# Status check
alembic current

# Show migrations history
alembic history

# Generate auto-migration
alembic revision --autogenerate -m "Add new table"

# Upgrade/downgrade
alembic upgrade head
alembic downgrade -1
```

### PostgreSQL Replication Check
```sql
-- On primary
SELECT * FROM pg_stat_replication;

-- On standby
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
```

---

## Appendix B: File Locations Summary

```
/home/akushnir/code-server/
├── migrations/                          # Root-level migrations
│   └── versions/
│       ├── 001_oauth2_schema.py
│       ├── 002_user_management_schema.py
│       ├── 003_team_organization_schema.py
│       ├── 004_advanced_authentication_schema.py
│       └── 005_api_gateway_schema.py
├── apps/
│   ├── auth-server/
│   │   ├── migrations/
│   │   │   └── optimize_database_indexes.py
│   │   └── requirements.txt              # sqlalchemy==2.0.23, alembic==1.13.0
│   ├── reputation_engine/
│   │   └── requirements.txt              # sqlalchemy==2.0.25
│   ├── execution-scheduler/
│   │   └── requirements.txt              # sqlalchemy==2.0.25
│   └── edge-agent/
│       └── requirements.txt              # sqlalchemy==2.0.25, alembic==1.13.0
├── scripts/
│   └── ops/
│       └── init-reputation-db.py         # SQLAlchemy Base initialization
├── terraform/
│   ├── modules/
│   │   ├── storage/
│   │   │   ├── main.tf
│   │   │   └── variables.tf              # postgres_volume_size_gb
│   │   └── core/
│   │       └── main.tf                   # Network topology references
│   └── environments/
│       ├── private/
│       └── air-gapped/
├── docker-compose.yml
├── docker-compose.cluster.yml            # Main database services
├── docker-compose.prod.yml
├── docker-compose.edge-agent.yml
├── .env.cluster                          # Cluster database config
├── .env.deployment                       # Dev database config
├── .env.schema.json                      # Database env var schema
└── DATABASE_INITIALIZATION_ANALYSIS.md   # This file
```

---

## Appendix C: Glossary

| Term | Definition |
|------|-----------|
| **Alembic** | Python database migration tool for SQLAlchemy |
| **SQLAlchemy** | Python ORM and SQL toolkit |
| **POSTGRES_INITDB_ARGS** | Arguments passed to PostgreSQL `initdb` during first startup |
| **WAL** | Write-Ahead Logging (for durability and replication) |
| **pg_isready** | PostgreSQL command to check readiness |
| **redis-cli** | Redis command-line client |
| **Qdrant** | Vector database for embeddings and semantic search |
| **Redpanda** | Kafka-compatible event streaming platform |
| **RDS** | AWS Relational Database Service (managed PostgreSQL) |
| **ElastiCache** | AWS managed Redis service |

---

**End of Report**
