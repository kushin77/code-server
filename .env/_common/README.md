# Environment Variable Consolidation (Phase 3) - SSOT Architecture

## Overview

This directory implements the **Single Source of Truth (SSOT)** architecture for environment variables, mirroring the Terraform consolidation completed in Phase 2.

## Problem Solved

Previously, environment variables were scattered across multiple .env files:
- `.env.base` - Base configuration
- `.env.infrastructure` - Infrastructure-specific settings
- `.env.deployment` - Deployment settings
- `.env.cluster` - Cluster settings
- `.env.production` - Production overrides
- `.env.consolidated` - Merged view (redundant)
- `.env.merged` - Merged view (redundant)

This created confusion about which file was the source of truth and made maintenance difficult.

## Solution Architecture

```
.env/
├── _common/
│   └── defaults          # SSOT: 41 shared variables for all environments
├── private/
│   └── overrides         # Private environment-specific overrides
└── air-gapped/
    └── overrides         # Air-gapped environment-specific overrides
```

### Variable Resolution Pattern

1. **Load common defaults** - All 41 shared variables from `.env/_common/defaults`
2. **Apply environment overrides** - Environment-specific values from `.env/private/overrides` or `.env/air-gapped/overrides`
3. **Environment wins** - If a variable is defined in both, environment value takes precedence

### Shared Variables (41 total)

**Core Configuration:**
- `APEX_DOMAIN` - Primary domain (SOURCE OF TRUTH)
- `AUTH_DOMAIN`, `APPSMITH_DOMAIN`, `CODE_SERVER_DOMAIN`, `IDE_DOMAIN`, `API_DOMAIN`, `REGISTRY_DOMAIN` - Derived domains
- `ADMIN_EMAIL`, `TLS_EMAIL` - Email configuration

**API & Protocol:**
- `API_PROTOCOL`, `API_HOST`, `API_PORT`, `API_ENDPOINT`
- `API_HEALTH_ENDPOINT`, `API_OAUTH_CALLBACK`

**Cluster & HA:**
- `CLUSTER_VIP`, `CLUSTER_HOST_1`, `CLUSTER_HOST_2`
- `PRIMARY_HOST`, `REPLICA_HOST`
- `DEPLOYMENT_MODE`, `REPLICA_ENABLED`, `REPLICATION_MODE`

**Database:**
- `DATABASE_HOST`, `DATABASE_PORT`, `POSTGRES_PORT`
- `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `POSTGRES_DB`
- `DATABASE_URL`, `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW`

**Redis:**
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`
- `REDIS_MAX_MEMORY`, `REDIS_EVICTION_POLICY`, `REDIS_APPENDONLY`

**Message Broker (Kafka/Redpanda):**
- `KAFKA_BROKER`, `KAFKA_TOPIC_PREFIX`, `REDPANDA_PORT`, `REDPANDA_BROKERS`
- `REDPANDA_PARTITIONS`, `REDPANDA_REPLICATION_FACTOR`

**Observability (Prometheus, Grafana, Loki, AlertManager):**
- `PROMETHEUS_PORT`, `PROMETHEUS_RETENTION`, `PROMETHEUS_SCRAPE_INTERVAL`
- `GRAFANA_PORT`, `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`
- `LOKI_PORT`, `LOKI_RETENTION_DAYS`, `ALERTMANAGER_PORT`

**OpenTelemetry/Tracing:**
- `OTEL_EXPORTER_OTLP_GRPC_PORT`, `OTEL_EXPORTER_OTLP_HTTP_PORT`
- `TEMPO_GRPC_PORT`, `TEMPO_HTTP_PORT`

## Implementation Steps

### Step 1: Create Common Defaults
```bash
mkdir -p .env/_common
# .env/_common/defaults created with 41 shared variables
```

### Step 2: Create Environment-Specific Overrides
```bash
mkdir -p .env/private .env/air-gapped
# .env/private/overrides - Private infrastructure values
# .env/air-gapped/overrides - Air-gapped infrastructure values
```

### Step 3: Update Script Sourcing
Scripts should now source variables in this pattern:

**For private environment:**
```bash
source .env/_common/defaults
[ -f .env/private/overrides ] && source .env/private/overrides
```

**For air-gapped environment:**
```bash
source .env/_common/defaults
[ -f .env/air-gapped/overrides ] && source .env/air-gapped/overrides
```

## Usage Examples

### Private Environment Sourcing
```bash
#!/usr/bin/env bash
export ENVIRONMENT=private
source .env/_common/defaults
[ -f .env/private/overrides ] && source .env/private/overrides

# Now use variables
echo "Deploying to: $API_HOST"
echo "Primary host: $PRIMARY_HOST"
echo "Replica host: $REPLICA_HOST"
```

### Air-Gapped Environment Sourcing
```bash
#!/usr/bin/env bash
export ENVIRONMENT=air-gapped
source .env/_common/defaults
[ -f .env/air-gapped/overrides ] && source .env/air-gapped/overrides

# Now use variables
echo "Deploying to: $API_HOST"
echo "Using registry: $REGISTRY_URL"
echo "Internal DNS: $APEX_DOMAIN"
```

### Runtime Environment Selection
```bash
#!/usr/bin/env bash
ENV=${ENVIRONMENT:-private}

source .env/_common/defaults

case "$ENV" in
    private)
        [ -f .env/private/overrides ] && source .env/private/overrides
        ;;
    air-gapped)
        [ -f .env/air-gapped/overrides ] && source .env/air-gapped/overrides
        ;;
    *)
        echo "Unknown environment: $ENV"
        exit 1
        ;;
esac
```

## Benefits

1. **Single Source of Truth** - All shared variables defined once in `.env/_common/defaults`
2. **Clear Environment Overrides** - Environment-specific values clearly separated
3. **Easy Maintenance** - Adding a new variable means updating only two files (common + environment)
4. **Reduced Duplication** - Eliminated redundant `.env.consolidated` and `.env.merged` files
5. **Mirrors Terraform Pattern** - Consistent with Phase 2 Terraform consolidation
6. **Scalable** - Easy to add new environments by creating new directories

## Phase 3 Status

### Completed ✓
- Created `.env/_common/defaults` with 41 shared variables
- Created `.env/private/overrides` with private environment values
- Created `.env/air-gapped/overrides` with air-gapped environment values
- Documented consolidation strategy and usage patterns

### Next Steps (Post-Phase 3)
- [ ] Update `scripts/_common/init.sh` to use new `.env/` structure
- [ ] Update deployment scripts to source environment files correctly
- [ ] Deprecate/remove redundant files (`.env.consolidated`, `.env.merged`, `.env.infrastructure`)
- [ ] Add environment variable validation during deployment
- [ ] Create `.env/_common/validation` script to verify all required variables are set
- [ ] Update CI/CD pipelines to use new `.env/` structure

## Deprecation Plan

The following files are now redundant and can be safely removed:
- `.env.consolidated` - Use `.env/_common/defaults` instead
- `.env.merged` - Use `.env/_common/defaults` instead
- `.env.infrastructure` - Merge remaining values into `.env/_common/defaults`

The following files should be kept temporarily for reference but can be phased out:
- `.env.base` - Merged into `.env/_common/defaults`
- `.env.production` - Values migrated to `.env/private/overrides`
- `.env.cluster` - Values migrated to `.env/private/overrides` and `.env/air-gapped/overrides`
- `.env.deployment` - Values migrated to environment overrides

## Related Documentation

- **Terraform Consolidation**: [terraform/environments/_common/README.md](../../terraform/environments/_common/README.md)
- **Installation Instructions**: [.instructions.md](../../.instructions.md)

---

**Date:** April 30, 2026  
**Phase:** 3 - Environment Variable Consolidation  
**Status:** SSOT Architecture Implemented
