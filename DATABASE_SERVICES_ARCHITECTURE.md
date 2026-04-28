# Database Services Architecture Diagram

## Current Database Stack Visualization

```
┌─────────────────────────────────────────────────────────────────┐
│                  ElevatedIQ DevOS Application Layer              │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ reputation-  │  │  execution-  │  │   memory-    │           │
│  │   engine     │  │  scheduler   │  │    engine    │           │
│  │  (port 8002) │  │  (port 8080) │  │  (port 8001) │           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                  │                 │                   │
└─────────┼──────────────────┼─────────────────┼───────────────────┘
          │                  │                 │
          │                  │                 │
    ┌─────────────────────────────────────────────────────────────┐
    │              DATABASE INITIALIZATION LAYER                   │
    ├─────────────────────────────────────────────────────────────┤
    │                                                               │
    │  ┌────────────────────┐  ┌────────────────────┐             │
    │  │  Alembic Migrations│  │  Environment Vars  │             │
    │  │  (Python)          │  │  (.env files)      │             │
    │  │                    │  │                    │             │
    │  │ • 001_oauth2       │  │ DB_USER=postgres   │             │
    │  │ • 002_user_mgmt    │  │ DB_PASSWORD=*****  │             │
    │  │ • 003_team_org     │  │ DB_NAME=kushnir_db │             │
    │  │ • 004_advanced_auth│  │ REDIS_PASSWORD=*** │             │
    │  │ • 005_api_gateway  │  │                    │             │
    │  └────────────────────┘  └────────────────────┘             │
    │                                                               │
    └─────────────────────────────────────────────────────────────┘
          │                  │                 │
          │                  │                 │
    ┌─────────────────────────────────────────────────────────────┐
    │              DATABASE SERVICES LAYER (Docker)                │
    ├─────────────────────────────────────────────────────────────┤
    │                                                               │
    │  ┌──────────────────┐  ┌──────────────────┐  ┌───────────┐  │
    │  │    PostgreSQL    │  │      Redis       │  │  Redpanda │  │
    │  │ (port 5432)      │  │ (port 6379)      │  │(port 9092)│  │
    │  │                  │  │                  │  │           │  │
    │  │ • postgres:16    │  │ • redis:7        │  │ • v26.1.6 │  │
    │  │ • 4GB RAM        │  │ • 4GB RAM        │  │ • Kafka   │  │
    │  │ • 2.0 CPU limit  │  │ • 2.0 CPU limit  │  │ • Brokers │  │
    │  │                  │  │                  │  │           │  │
    │  └────────┬─────────┘  └────────┬─────────┘  └──────┬────┘  │
    │           │                     │                   │        │
    │           │                     │                   │        │
    │  ┌────────┴─────────┐  ┌────────┴─────────┐         │        │
    │  │  postgres_data   │  │   redis_data     │         │        │
    │  │ Volume Mount     │  │  Volume Mount    │         │        │
    │  └──────────────────┘  └──────────────────┘         │        │
    │                                                      │        │
    │                                  ┌──────────────────┘        │
    │                                  │                           │
    │                        ┌──────────┴─────────┐                │
    │                        │  redpanda_data     │                │
    │                        │  Volume Mount      │                │
    │                        └────────────────────┘                │
    │                                                               │
    │  ┌──────────────────┐                                         │
    │  │      Qdrant      │                                         │
    │  │ (port 6333)      │                                         │
    │  │                  │                                         │
    │  │ • qdrant:v1.7.0  │                                         │
    │  │ • 2.0 CPU limit  │                                         │
    │  │ • 2GB RAM        │                                         │
    │  │                  │                                         │
    │  └────────┬─────────┘                                         │
    │           │                                                   │
    │  ┌────────┴─────────┐                                         │
    │  │  qdrant_data     │                                         │
    │  │  Volume Mount    │                                         │
    │  └──────────────────┘                                         │
    │                                                               │
    └─────────────────────────────────────────────────────────────┘
          ▲                  ▲                 ▲
          │                  │                 │
    ┌─────────────────────────────────────────────────────────────┐
    │                  STORAGE LAYER                                │
    ├─────────────────────────────────────────────────────────────┤
    │                                                               │
    │  Volume Paths:                                                │
    │  • postgres_data:        /var/lib/postgresql/data            │
    │  • redis_data:           /data                               │
    │  • redpanda_data:        /var/lib/redpanda/data              │
    │  • qdrant_data:          /qdrant/storage                     │
    │                                                               │
    │  Backup Paths:                                                │
    │  • postgres_backup:      ${storage_mount_path}/backups/…     │
    │                                                               │
    └─────────────────────────────────────────────────────────────┘
```

---

## Database Initialization Flow

```
Container Start
    │
    ├─ PostgreSQL
    │    │
    │    ├─ Execute POSTGRES_INITDB_ARGS
    │    │   └─ UTF-8 encoding, WAL settings
    │    │
    │    ├─ Create Database: ${DB_NAME}
    │    ├─ Create User: ${DB_USER}
    │    ├─ Set Password: ${DB_PASSWORD}
    │    │
    │    ├─ Health Check: pg_isready
    │    │
    │    └─ Ready for Migrations ✓
    │
    ├─ Application Startup
    │    │
    │    ├─ Load DATABASE_URL env var
    │    │   (postgresql://user:pass@postgres:5432/db)
    │    │
    │    ├─ Execute Alembic Migrations
    │    │   ├─ 001_oauth2_schema.py
    │    │   ├─ 002_user_management_schema.py
    │    │   ├─ 003_team_organization_schema.py
    │    │   ├─ 004_advanced_authentication_schema.py
    │    │   ├─ 005_api_gateway_schema.py
    │    │   └─ optimize_database_indexes.py
    │    │
    │    ├─ Create Indexes & Constraints
    │    └─ Database Ready ✓
    │
    ├─ Redis
    │    │
    │    ├─ Start with AOF (Append-Only File)
    │    ├─ Set Password: ${REDIS_PASSWORD}
    │    ├─ Max Memory: 6GB
    │    ├─ Eviction Policy: allkeys-lru
    │    │
    │    └─ Ready for Caching ✓
    │
    └─ Application Ready ✓
```

---

## Environment Variable Hierarchy

```
System Environment (.env files)
    │
    ├─ .env.cluster (Production)
    │   ├─ DB_NAME=kushnir_db
    │   ├─ DB_USER=postgres
    │   ├─ DB_PASSWORD=k8s_secure_postgres_2026
    │   ├─ REDIS_PASSWORD=redis_secure_2026
    │   └─ POSTGRES_INITDB_ARGS=...
    │
    ├─ .env.deployment (Development)
    │   ├─ DB_NAME=devos
    │   ├─ DB_USER=postgres
    │   ├─ DB_PASSWORD=postgres-dev-password
    │   └─ REDIS_PASSWORD=redis-dev-password
    │
    └─ .env.schema.json (Schema)
        ├─ DB_USER (description, type, usage)
        ├─ DB_PASSWORD (sensitive)
        ├─ DB_NAME
        ├─ DATABASE_URL (computed)
        └─ REDIS_PASSWORD
            │
            ▼
        Docker-Compose YAML
            │
            ├─ POSTGRES_DB=${DB_NAME}
            ├─ POSTGRES_USER=${DB_USER}
            ├─ POSTGRES_PASSWORD=${DB_PASSWORD}
            └─ POSTGRES_INITDB_ARGS=...
                │
                ▼
            PostgreSQL Service
                │
                └─ Database Initialized
```

---

## Migration Workflow

```
Source Code (migrations/versions/*.py)
         │
         ├─ Tracked by Alembic
         │   └─ alembic_version table
         │
         ▼
  Developer runs: alembic upgrade head
         │
         ├─ Alembic reads migrations
         ├─ Connects to PostgreSQL via DATABASE_URL
         ├─ Executes each migration in order
         │   ├─ CREATE TABLE
         │   ├─ CREATE INDEX
         │   ├─ ALTER TABLE
         │   └─ etc.
         │
         ▼
  Database Schema Updated
         │
         ├─ Version 001: OAuth2 tables
         ├─ Version 002: User tables
         ├─ Version 003: Team tables
         ├─ Version 004: Auth tables
         ├─ Version 005: API Gateway tables
         └─ Indexes: Performance tuning
         │
         ▼
  Application Ready to Use
```

---

## Service Dependencies

```
reputation-engine
    │
    ├─ Depends: postgres (service_healthy)
    ├─ Depends: redpanda (service_healthy)
    ├─ Depends: opa (service_healthy)
    │
    └─ Environment:
        ├─ DATABASE_URL
        ├─ KAFKA_BROKER=redpanda:9092
        └─ OPA_URL=http://opa:8181

execution-scheduler
    │
    ├─ Depends: postgres (service_healthy)
    ├─ Depends: redpanda (service_healthy)
    │
    └─ Environment:
        ├─ DATABASE_URL
        ├─ KAFKA_BROKER=redpanda:9092
        └─ SCHEDULER_API_KEY

auth-server
    │
    ├─ Uses: Alembic migrations
    ├─ Uses: SQLAlchemy ORM
    │
    └─ Environment:
        └─ DATABASE_URL (auto-constructed)
```

---

## Resource Allocation

```
PostgreSQL (16-alpine)
├─ CPU Limit:     2.0 cores
├─ CPU Reserve:   1.0 core
├─ Memory Limit:  4 GB
├─ Memory Reserve: 2 GB
└─ Restart:       unless-stopped

Redis (7-alpine)
├─ CPU Limit:     2.0 cores
├─ CPU Reserve:   1.0 core
├─ Memory Limit:  4 GB
│   └─ Max Used:  6 GB (maxmemory config)
├─ Memory Reserve: 2 GB
└─ Restart:       unless-stopped

Redpanda (v26.1.6)
├─ CPU Limit:     TBD (from docker-compose)
├─ Memory Limit:  TBD
└─ Restart:       unless-stopped

Qdrant (v1.7.0)
├─ CPU Limit:     2.0 cores
├─ CPU Reserve:   1.0 core
├─ Memory Limit:  2 GB
├─ Memory Reserve: 1 GB
└─ Restart:       unless-stopped
```

---

## Network Architecture

```
┌─────────────────────────────────────────────┐
│         Docker Networks                      │
├─────────────────────────────────────────────┤
│                                              │
│  services network (inter-service comms)     │
│  ├─ reputation-engine                       │
│  ├─ execution-scheduler                     │
│  ├─ memory-engine                           │
│  ├─ activity-feed                           │
│  ├─ postgres                                │
│  ├─ redis                                   │
│  ├─ redpanda                                │
│  └─ qdrant                                  │
│                                              │
│  database network (postgres isolation)      │
│  ├─ postgres                                │
│  ├─ reputation-engine                       │
│  └─ execution-scheduler                     │
│                                              │
│  ingress network (external entry)           │
│  └─ env-provisioner                         │
│                                              │
└─────────────────────────────────────────────┘
```

---

## Key Metrics

| Metric | PostgreSQL | Redis | Redpanda | Qdrant |
|--------|-----------|-------|----------|--------|
| **Image Size** | alpine (small) | alpine (small) | ~1GB | ~500MB |
| **Port** | 5432 | 6379 | 9092 | 6333 |
| **CPU Limit** | 2.0 | 2.0 | TBD | 2.0 |
| **Memory Limit** | 4GB | 4GB | TBD | 2GB |
| **Storage** | Persistent | Persistent | Persistent | Persistent |
| **Health Check** | pg_isready | redis-cli | HTTP | TCP |
| **Dependencies** | None | None | None | None |
| **Network Isolation** | Yes (database) | No (services) | No (services) | No (services) |

