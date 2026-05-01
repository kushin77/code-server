# Environment Configuration SSOT Documentation

## Overview

As of April 30, 2026, all environment configuration has been consolidated into a **Single Source of Truth (SSOT)** architecture to eliminate duplications and prevent configuration drift.

### Before: Configuration Chaos

Previously, configuration was scattered across **57 duplicated variables** across 4 files:
- `.env.production` (118 vars) - Production overrides and secrets
- `.env.cluster` (118 vars) - HA cluster networking
- `.env.deployment` (148 vars) - Deployment-specific settings
- `.env.infrastructure` (68 vars) - Infrastructure URLs

This created maintenance headaches:
- ❌ Variable duplication with inconsistent values
- ❌ No single source of truth for defaults
- ❌ Difficult to track which env file to update
- ❌ Risk of configuration drift between environments

### After: SSOT Architecture

Now, configuration is managed through a **priority-based loading hierarchy**:

```
┌─────────────────────────────────────────────────────────┐
│ 1. HIGHEST: Environment Variables (set externally)     │
│    - Override anything else                            │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 2. .env.base (CANONICAL SSOT)                         │
│    - All variables with sensible defaults             │
│    - 20 organized sections                            │
│    - ~450 lines of comprehensive config               │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 3. .env.infrastructure (Optional)                      │
│    - Infrastructure URLs and endpoints                 │
│    - Docker/K8s host IPs                               │
│    - Only override if needed                           │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 4. .env.deployment (Optional)                          │
│    - Deployment mode settings                         │
│    - Dev/staging/prod specific values                 │
│    - Only override if needed                          │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 5. .env.cluster (Optional)                             │
│    - HA cluster settings                              │
│    - Multi-node cluster IPs                           │
│    - Only override if needed                          │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 6. LOWEST: .env.production (Optional)                  │
│    - Production-specific overrides and secrets        │
│    - Final secret values                              │
│    - Only override if needed                          │
└─────────────────────────────────────────────────────────┘
```

## Files

### 1. `.env.base` (CANONICAL - DO NOT MODIFY)
**Purpose**: Single source of truth with all variables and sensible defaults.

**Contains**: ~20 organized sections covering:
- Core domain & identity
- API & protocol configuration
- Cluster & HA settings
- Database & Redis
- Message broker (Redpanda/Kafka)
- Observability & monitoring
- OpenTelemetry & tracing
- AI/ML & vector DB
- Policy engine (OPA)
- Application services
- Autonomous agents
- OAuth & authentication
- Appsmith configuration
- Logging & debugging
- API gateway (Caddy)
- External integrations
- Storage & NAS
- Deployment & feature flags
- Health check configuration

**Usage**: Source this first in all scripts
```bash
source .env.base
```

### 2. `.env.example` (PUBLIC DOCUMENTATION)
**Purpose**: Template for new environments, documents all variables.

**Contains**: All variables from `.env.base` with:
- Descriptive comments
- Placeholder values (no secrets)
- Example patterns
- Configuration guidance

**Usage**: Copy to `.env` when setting up a new environment
```bash
cp .env.example .env
# Edit .env and fill in your values
```

### 3. `.env.production` (SECRETS - PRIVATE)
**Purpose**: Production-specific overrides and actual secrets.

**Contains Only**:
- Real secret values
- Production-specific port/host overrides (if different from base)
- Credentials for external services

**Best Practice**:
- Keep in GSM or secrets vault, NOT in git
- Load last to override all other files
- Set via CI/CD secrets management

**Load**: Last in priority hierarchy

### 4. `.env.cluster` (OPTIONAL - ENVIRONMENT SPECIFIC)
**Purpose**: Cluster-specific networking and HA configuration.

**Contains Only**:
- Cluster VIP and host IPs
- HA replication settings
- Multi-node cluster configuration

**Load**: After `.env.deployment`, before `.env.production`

### 5. `.env.deployment` (OPTIONAL - ENVIRONMENT SPECIFIC)
**Purpose**: Deployment mode settings and environment-specific tweaks.

**Contains Only**:
- Deployment mode (dev/staging/prod)
- Environment-specific port bindings
- Deployment automation flags

**Load**: After `.env.infrastructure`, before `.env.cluster`

### 6. `.env.infrastructure` (OPTIONAL - ENVIRONMENT SPECIFIC)
**Purpose**: Infrastructure URLs and deployment target endpoints.

**Contains Only**:
- API host/port/protocol
- Service endpoints
- Docker/Kubernetes host information
- Network endpoints

**Load**: After `.env.base`, before `.env.deployment`

## Usage Guide

### For Scripts and Applications

Load configuration in priority order:

```bash
#!/bin/bash

# Load configuration (priority order)
source .env.base                              # Canonical defaults
[ -f .env.infrastructure ] && source .env.infrastructure
[ -f .env.deployment ] && source .env.deployment
[ -f .env.cluster ] && source .env.cluster
[ -f .env.production ] && source .env.production

# Now use variables
echo "Database: $DATABASE_HOST:$DATABASE_PORT"
echo "Redis: $REDIS_HOST:$REDIS_PORT"
```

### For Docker Compose

Docker Compose automatically loads `.env` file in this order:

```bash
# Create .env as a symlink to load all files
cat .env.base .env.infrastructure .env.deployment .env.cluster .env.production > .env

# Or use explicit file loading in docker-compose.yml
docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  --env-file .env.base \
  --env-file .env.infrastructure \
  up -d
```

### For CI/CD Pipelines

In GitHub Actions:

```yaml
jobs:
  deploy:
    steps:
      - name: Load configuration
        run: |
          source .env.base
          [ -f .env.infrastructure ] && source .env.infrastructure
          [ -f .env.deployment ] && source .env.deployment
          [ -f .env.production ] && source .env.production
          
      - name: Deploy
        run: ./scripts/deploy.sh
```

## Migration Guide

### For Existing Deployments

1. **Backup existing .env files**:
   ```bash
   cp .env.production .env.production.backup
   cp .env.cluster .env.cluster.backup
   cp .env.deployment .env.deployment.backup
   cp .env.infrastructure .env.infrastructure.backup
   ```

2. **Stop any running containers**:
   ```bash
   docker compose down
   ```

3. **Replace old files with new SSOT structure**:
   - Keep `.env.base` (canonical - do not edit)
   - Keep `.env.example` (for documentation)
   - Keep existing `.env.production`, `.env.cluster`, etc. (they override base defaults)

4. **Verify configuration**:
   ```bash
   source .env.base
   source .env.infrastructure 2>/dev/null || true
   source .env.deployment 2>/dev/null || true
   source .env.cluster 2>/dev/null || true
   source .env.production 2>/dev/null || true
   
   # Verify critical variables
   echo "DB Host: $DATABASE_HOST"
   echo "Redis Host: $REDIS_HOST"
   ```

5. **Start containers**:
   ```bash
   docker compose up -d
   ```

## Best Practices

### 1. Never Modify `.env.base` for Environment-Specific Values
❌ **Wrong**: Editing `.env.base` to set `DATABASE_HOST=production-db`
✅ **Right**: Set `DATABASE_HOST=production-db` in `.env.production`

### 2. Use `.env.base` for Defaults Only
❌ **Wrong**: `.env.base` contains `REDIS_PASSWORD=production-secret-123`
✅ **Right**: `.env.base` contains `REDIS_PASSWORD=${REDIS_PASSWORD:-redis-dev-password}`

### 3. Keep Secrets Private
❌ **Wrong**: Committing `.env.production` with real secrets to git
✅ **Right**: Manage `.env.production` via GSM, GitHub Secrets, or CI/CD

### 4. Document Every Variable
- All variables in `.env.base` should have comments explaining their purpose
- Use `.env.example` as public documentation
- Group related variables into logical sections

### 5. Test After Changes
Always verify configuration loads correctly:
```bash
source .env.base && \
[ -f .env.infrastructure ] && source .env.infrastructure && \
env | grep -E "^(DATABASE|REDIS|KAFKA|PROMETHEUS)" | head -10
```

## Configuration Sections Reference

| Section | Variables | Purpose |
|---------|-----------|---------|
| Core Domain | APEX_DOMAIN, AUTH_DOMAIN, TLS_EMAIL | Primary identifiers |
| API & Protocol | API_PROTOCOL, API_HOST, API_PORT | Service connectivity |
| Cluster & HA | CLUSTER_VIP, REPLICA_ENABLED, REPLICATION_MODE | High availability |
| Database | DATABASE_HOST, DB_USER, DB_PASSWORD | PostgreSQL |
| Redis | REDIS_HOST, REDIS_PASSWORD, REDIS_MAX_MEMORY | Caching & sessions |
| Message Broker | KAFKA_BROKER, REDPANDA_PORT | Event streaming |
| Observability | PROMETHEUS_PORT, GRAFANA_PORT, LOKI_PORT | Monitoring |
| OTEL & Tracing | OTEL_EXPORTER_OTLP_ENDPOINT, TEMPO_GRPC_PORT | Distributed tracing |
| AI/ML | OLLAMA_URL, QDRANT_API_KEY, OPENAI_API_KEY | ML services |
| Policy | OPA_URL, OPA_ADMIN_TOKEN | Authorization |
| App Services | SCHEDULER_PORT, MEMORY_ENGINE_PORT, etc. | Microservices |
| Agents | AGENT_CODE_REVIEWER_PORT, AGENT_RUNTIME_PORT | Autonomous agents |
| Auth | OAUTH_ENABLED, OAUTH_GOOGLE_CLIENT_ID, etc. | Authentication |
| Appsmith | APPSMITH_ENCRYPTION_PASSWORD, APPSMITH_MONGODB_URI | IDE config |
| Logging | LOG_LEVEL, LOG_FORMAT, AUDIT_LOGGING_ENABLED | Observability |
| Caddy | CADDY_EMAIL, CADDY_AUTO_HTTPS | API Gateway |
| Integrations | SLACK_BOT_TOKEN, SENTRY_DSN | External services |
| Storage | NAS_HOST, NAS_MOUNT_PATH | Persistent storage |
| Deployment | DEPLOYMENT_MODE, DEPLOYMENT_AUTO_ROLLBACK | Deployment control |
| Health Checks | HEALTH_CHECK_TIMEOUT, HEALTH_CHECK_MAX_ATTEMPTS | Service health |

## Troubleshooting

### Q: Variable not found even though it's in `.env.base`
A: Ensure files are sourced in correct order:
```bash
source .env.base  # Must be first
echo $VARIABLE_NAME  # Should work now
```

### Q: Getting old/wrong value for a variable
A: Check load order. Later files override earlier ones:
```bash
source .env.base
echo "REDIS_PASSWORD from base: $REDIS_PASSWORD"
source .env.production
echo "REDIS_PASSWORD from production: $REDIS_PASSWORD"
```

### Q: Can't find `.env.production` in git
A: That's by design! Secrets shouldn't be in git. Check:
- GitHub Secrets for CI/CD
- Google Secret Manager for production
- Local `.env.production` ignored by `.gitignore`

### Q: Which file should I edit?
Use this decision tree:
- Is it a default that applies everywhere? → `.env.base`
- Is it only for production? → `.env.production`
- Is it infrastructure-specific? → `.env.infrastructure`
- Is it for HA cluster? → `.env.cluster`
- Is it deployment-specific? → `.env.deployment`

## Related Issues

- **Issue #3117**: Environment consolidation and SSOT creation (RESOLVED)
- **Issue #3118**: GitHub Actions CI for compose validation
- **Issue #3121**: Docker Compose profiles refactoring

---

*Last Updated: April 30, 2026*
*Status: SSOT Architecture Implemented and Documented*
