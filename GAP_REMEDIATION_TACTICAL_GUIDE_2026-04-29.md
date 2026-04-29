# Deployment Gap Reconciliation - Tactical Execution Guide

**Status:** Ready for Implementation  
**Created:** April 29, 2026  
**Risk Level:** Medium (P0 items have data sync requirements)

---

## Quick Start: Gap Remediation Commands

### Phase 1: Database Replication (CRITICAL - Must Do First)

#### 1.1 Primary Host Setup (192.168.168.31)

```bash
#!/bin/bash
set -e

HOST="192.168.168.31"
REPL_USER="replica_user"
REPL_PASSWORD="${REPLICA_PASSWORD:-replica_secure_pwd_2026}"

echo "=== PHASE 1: Configure Primary PostgreSQL for Replication ==="

ssh akushnir@$HOST << 'PRIM_EOF'
set -e

echo "1. Backing up current postgresql.conf..."
docker exec code-server-postgres bash -c 'cp /var/lib/postgresql/data/postgresql.conf /var/lib/postgresql/data/postgresql.conf.bak'

echo "2. Adding replication parameters..."
docker exec code-server-postgres bash -c '
  conf_file="/var/lib/postgresql/data/postgresql.conf"
  
  # Check if already configured
  grep -q "^max_wal_senders" "$conf_file" && {
    echo "Already configured, skipping..."
    exit 0
  }
  
  # Add replication parameters at end of file
  cat >> "$conf_file" << CONFIG

# Replication Configuration
max_wal_senders = 3
max_replication_slots = 3
wal_level = replica
hot_standby = on
hot_standby_feedback = on
wal_keep_size = 1GB
CONFIG
'

echo "3. Creating replication slot..."
docker exec code-server-postgres psql -U postgres -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot') THEN
      PERFORM pg_create_physical_replication_slot('replica_slot');
      RAISE NOTICE 'Created replication slot: replica_slot';
    ELSE
      RAISE NOTICE 'Replication slot already exists';
    END IF;
  END
  \$\$;
" || echo "Slot creation skipped (may already exist)"

echo "4. Creating replication user..."
docker exec code-server-postgres psql -U postgres -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_user WHERE usename = 'replica_user') THEN
      CREATE ROLE replica_user WITH LOGIN REPLICATION PASSWORD 'replica_secure_pwd_2026';
      RAISE NOTICE 'Created replication user: replica_user';
    ELSE
      RAISE NOTICE 'Replication user already exists';
    END IF;
  END
  \$\$;
" || echo "User creation skipped (may already exist)"

echo "5. Updating pg_hba.conf for replica connections..."
docker exec code-server-postgres bash -c '
  hba_file="/var/lib/postgresql/data/pg_hba.conf"
  
  # Check if already configured
  grep -q "replication.*replica_user.*192.168.168.42" "$hba_file" && {
    echo "Already configured, skipping..."
    exit 0
  }
  
  # Add replication entry
  echo "host replication replica_user 192.168.168.42/32 md5" >> "$hba_file"
'

echo "6. Restarting PostgreSQL on primary..."
docker restart code-server-postgres
echo "Waiting for postgres to be ready..."
sleep 10

docker exec code-server-postgres psql -U postgres -c "SELECT version();"
echo "✓ Primary PostgreSQL configured successfully"

PRIM_EOF

echo "✓ Primary host configuration complete"
```

#### 1.2 Replica Host Setup (192.168.168.42)

```bash
#!/bin/bash
set -e

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
REPL_USER="replica_user"
REPL_PASSWORD="${REPLICA_PASSWORD:-replica_secure_pwd_2026}"

echo "=== PHASE 1.2: Configure Replica PostgreSQL (Standby) ==="

ssh akushnir@$REPLICA_HOST << 'REPL_EOF'
set -e

PRIMARY_HOST="192.168.168.31"
REPL_USER="replica_user"
REPL_PASSWORD="replica_secure_pwd_2026"

echo "1. Stopping postgres if running..."
docker stop code-server-postgres 2>/dev/null || true
sleep 5

echo "2. Backing up existing data (safety first!)..."
docker run --rm \
  -v code-server-enterprise-ops_postgres_data:/data \
  -v /tmp:/backup \
  alpine bash -c '
    tar czf /backup/postgres-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C /data . 2>/dev/null || true
    echo "Backup saved to /tmp/postgres-backup-*.tar.gz"
  '

echo "3. Clearing postgres data directory for pg_basebackup..."
docker exec -u 0 code-server-postgres bash -c '
  rm -rf /var/lib/postgresql/data/*
' 2>/dev/null || {
  # If postgres not running, use volume directly
  docker run --rm -v code-server-enterprise-ops_postgres_data:/data \
    alpine sh -c "rm -rf /data/*"
}

echo "4. Running pg_basebackup from primary..."
export PGPASSWORD="$REPL_PASSWORD"
docker run --rm \
  -e PGPASSWORD \
  -v code-server-enterprise-ops_postgres_data:/data \
  postgres:15 bash -c "
    pg_basebackup \
      -h $PRIMARY_HOST \
      -U $REPL_USER \
      -D /data \
      -Fp \
      -Xs \
      -P \
      -v
    
    echo 'pg_basebackup completed successfully'
  "

echo "5. Fixing permissions on replicated data..."
docker run --rm \
  -v code-server-enterprise-ops_postgres_data:/data \
  alpine chown -R 999:999 /data

echo "6. Creating recovery.conf for standby mode..."
docker run --rm \
  -v code-server-enterprise-ops_postgres_data:/data \
  alpine bash -c "
    cat > /data/postgresql.auto.conf << 'STANDBY'
# PostgreSQL Standby Configuration
standby_mode = true
recovery_target_timeline = 'latest'
primary_conninfo = 'host=$PRIMARY_HOST port=5432 user=$REPL_USER password=$REPL_PASSWORD sslmode=prefer'
STANDBY
    chmod 600 /data/postgresql.auto.conf
    echo 'Created postgresql.auto.conf for standby'
  "

echo "7. Starting postgres in standby mode..."
docker start code-server-postgres
sleep 10

echo "8. Verifying standby status..."
docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"

echo "✓ Replica PostgreSQL configured successfully"

REPL_EOF

echo "✓ Replica host configuration complete"
```

#### 1.3 Verification Script

```bash
#!/bin/bash

echo "=== REPLICATION VERIFICATION ==="

echo ""
echo "--- PRIMARY: Replication Slots ---"
ssh akushnir@192.168.168.31 \
  "docker exec code-server-postgres psql -U postgres -c \
    'SELECT slot_name, slot_type, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;'"

echo ""
echo "--- PRIMARY: Active Replication Connections ---"
ssh akushnir@192.168.168.31 \
  "docker exec code-server-postgres psql -U postgres -c \
    'SELECT client_addr, usename, application_name, state, sync_state, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;'"

echo ""
echo "--- REPLICA: Recovery Status ---"
ssh akushnir@192.168.168.42 \
  "docker exec code-server-postgres psql -U postgres -c \
    'SELECT pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();'"

echo ""
echo "--- REPLICA: Replication Lag ---"
ssh akushnir@192.168.168.42 \
  "docker exec code-server-postgres psql -U postgres -c \
    'SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_time())) as lag_seconds;'"

echo ""
echo "✓ Verification complete"
```

---

### Phase 2: Enforce Resource Limits

#### 2.1 Generate Resource Limit Configuration

```bash
#!/bin/bash

cat > /tmp/resource-limits-patch.tf << 'LIMITS_TF'
# Add to terraform/environments/private/modules/stack/containers-platform.tf

locals {
  resource_limits = {
    postgres = {
      memory = "4G"
      cpus   = "2"
    }
    redis = {
      memory = "2G"
      cpus   = "1.5"
    }
    redpanda = {
      memory = "4G"
      cpus   = "2"
    }
    prometheus = {
      memory = "1G"
      cpus   = "1"
    }
    grafana = {
      memory = "1G"
      cpus   = "1"
    }
    loki = {
      memory = "1G"
      cpus   = "1"
    }
    # Default for all agent/app services
    default = {
      memory = "1G"
      cpus   = "1"
    }
  }
}

# Apply to all containers in docker_container resources:
memory = lookup(
  local.resource_limits,
  replace(var.service_name, "-", "_"),
  local.resource_limits["default"]
).memory
LIMITS_TF

echo "Resource limits configuration generated at /tmp/resource-limits-patch.tf"
echo "Review and apply to your terraform configuration"
```

#### 2.2 Quick Docker-Compose Approach

```bash
#!/bin/bash

# Add to docker-compose.yml for each service
cat > /tmp/deploy-limits.sh << 'DEPLOY'
#!/bin/bash

# Services requiring resource limits
SERVICES=(
  "postgres:4G:2"
  "redis:2G:1.5"
  "redpanda:4G:2"
  "prometheus:1G:1"
  "grafana:1G:1"
  "loki:1G:1"
  "tempo:1G:1"
  "qdrant:2G:1"
  "agent-runtime:1G:1"
  "multimodal-ai:1G:1"
  "edge-agent:1G:1"
  "activity-feed:512M:0.5"
  "memory-engine:512M:0.5"
  "reputation-engine:512M:0.5"
  "paperclip:512M:0.5"
  "execution-scheduler:512M:0.5"
  "env-provisioner:512M:0.5"
)

for service_config in "${SERVICES[@]}"; do
  IFS=':' read -r service memory cpus <<< "$service_config"
  
  echo "Updating limits for: code-server-$service"
  # Update constraints in compose file
  # This is a placeholder - actual update requires compose file editing
done

DEPLOY

chmod +x /tmp/deploy-limits.sh
echo "Deployment script created at /tmp/deploy-limits.sh"
```

---

### Phase 3: Add Health Checks

#### 3.1 Health Check Templates

```yaml
# Add these health checks to docker-compose.yml for services lacking them

agent-runtime:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9005/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

agent-code-reviewer:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9001/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

agent-doc-writer:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9003/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

agent-test-generator:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9004/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

agent-incident-responder:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9002/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

multimodal-ai:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8040/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

activity-feed:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8004/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

edge-agent:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8060/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

reputation-engine:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8002/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

execution-scheduler:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

env-provisioner:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

memory-engine:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8001/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

paperclip:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8007/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

oauth2-proxy:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4180/ping"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

gitlab-runner:
  healthcheck:
    test: ["CMD", "gitlab-runner", "verify"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 60s
```

#### 3.2 Deployment

```bash
#!/bin/bash

echo "Deploying health checks..."

# 1. Update compose files
# (Paste the health check YAML above into docker-compose.yml and docker-compose.enterprise.yml)

# 2. Restart services
ssh akushnir@192.168.168.31 "
  cd ~/code-server-enterprise
  docker-compose down
  docker-compose up -d
"

ssh akushnir@192.168.168.42 "
  cd ~/code-server-enterprise
  docker-compose down
  docker-compose up -d
"

# 3. Wait for health checks to initialize
echo "Waiting for health checks to initialize..."
sleep 60

# 4. Verify
for host in 192.168.168.31 192.168.168.42; do
  echo ""
  echo "=== Health Check Status on $host ==="
  ssh akushnir@$host "
    docker ps --format 'table {{.Names}}\t{{.Status}}' | \
      grep -E 'healthy|unhealthy|health: starting'
  "
done
```

---

### Phase 4: Volume Cleanup

#### 4.1 Audit Script

```bash
#!/bin/bash

echo "=== VOLUME AUDIT ==="

for host in 192.168.168.31 192.168.168.42; do
  echo ""
  echo "--- $host ---"
  ssh akushnir@$host << AUDIT
set -e

echo "1. Volumes in use by containers:"
docker ps -a --format '{{.Names}}' | while read container; do
  docker inspect "\$container" 2>/dev/null | jq -r '.Mounts[] | select(.Type=="volume") | .Name' || true
done | sort -u | wc -l

echo "2. All volumes:"
docker volume ls -q | wc -l

echo "3. Potentially orphaned (not used by any container):"
comm -23 <(docker volume ls -q | sort) \
         <(docker ps -a --format '{{.Names}}' | while read c; do 
             docker inspect "\$c" 2>/dev/null | jq -r '.Mounts[] | select(.Type=="volume") | .Name' || true
           done | sort -u) | head -10

AUDIT
done

echo ""
echo "✓ Audit complete"
```

#### 4.2 Safe Cleanup

```bash
#!/bin/bash

echo "=== SAFE VOLUME CLEANUP ==="

for host in 192.168.168.31 192.168.168.42; do
  echo ""
  echo "--- Cleaning $host ---"
  ssh akushnir@$host << CLEANUP
set -e

# Back up before cleaning
echo "1. Creating backup..."
docker run --rm \
  -v /var/lib/docker/volumes:/volumes \
  -v /tmp:/backup \
  alpine tar czf /backup/docker-volumes-backup-$(date +%Y%m%d).tar.gz -C /volumes . 2>/dev/null || true

# Remove only unrelated volumes (not code-server or explicitly managed)
echo "2. Pruning unused volumes..."
docker volume prune -f --filter "label!=keep=true" 2>/dev/null || true

echo "3. Verifying remaining volumes..."
docker volume ls | head -20

CLEANUP
done

echo "✓ Cleanup complete. Backups saved to /tmp/docker-volumes-backup-*.tar.gz"
```

---

### Phase 5: Remove Orphaned Containers

#### 5.1 Purebliss Cleanup

```bash
#!/bin/bash

echo "=== REMOVING ORPHANED CONTAINERS ==="

ssh akushnir@192.168.168.42 << 'ORPHAN'
set -e

echo "1. Finding orphaned containers (not in code-server namespace)..."
docker ps -a --format '{{.Names}}' | grep -v '^code-server-' | grep -v '^purebliss-' || true

echo ""
echo "2. Removing purebliss-scraper..."
docker rm -f purebliss-scraper 2>/dev/null || echo "Already removed"

echo ""
echo "3. Removing orphaned purebliss containers..."
docker rm -f purebliss-redis-scraper purebliss-postgres-scraper purebliss-prometheus-scraper purebliss-api-instance purebliss-postgres-instance purebliss-redis-instance 2>/dev/null || true

echo "✓ Orphaned containers removed"

ORPHAN

echo "✓ Cleanup complete on replica"
```

---

### Phase 6: Full Verification

#### 6.1 Comprehensive Status Check

```bash
#!/bin/bash

echo "================================================"
echo "COMPREHENSIVE DEPLOYMENT STATUS VERIFICATION"
echo "================================================"

for host in 192.168.168.31 192.168.168.42; do
  echo ""
  echo "=== $host ==="
  
  ssh akushnir@$host << VERIFY
set -e

echo ""
echo "1. RUNNING CONTAINERS:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'  | head -45

echo ""
echo "2. HEALTH CHECK STATUS:"
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'healthy|unhealthy|health: starting' | wc -l
echo "   (Should be ~41 healthy)"

echo ""
echo "3. RESOURCE LIMITS:"
docker inspect \$(docker ps -aq | head -5) 2>/dev/null | \
  jq '.[] | {name: .Name, memory: .HostConfig.Memory}' | \
  grep -c '"memory"' || echo "0"
echo "   (Should be 41 with limits set)"

echo ""
echo "4. VOLUME COUNT:"
docker volume ls -q | wc -l
echo "   (Should be ~16-20 after cleanup)"

echo ""
echo "5. NETWORK COUNT:"
docker network ls --format '{{.Name}}' | wc -l
echo "   (Should be ~9-10)"

echo ""
echo "6. DATABASE REPLICATION STATUS:"
docker exec code-server-postgres psql -U postgres -c \
  "SELECT CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END;" 2>/dev/null || echo "Query failed"

VERIFY

done

echo ""
echo "================================================"
echo "VERIFICATION COMPLETE"
echo "================================================"
```

---

## Testing & Validation

### Pre-Implementation Checklist

```bash
# 1. Document current state
ssh akushnir@192.168.168.31 "docker ps -a > /tmp/primary-state-before.txt"
ssh akushnir@192.168.168.42 "docker ps -a > /tmp/replica-state-before.txt"
ssh akushnir@192.168.168.31 "docker volume ls > /tmp/primary-volumes-before.txt"

# 2. Backup databases
ssh akushnir@192.168.168.31 "
  docker exec code-server-postgres pg_dump -U postgres code_server > /tmp/db-backup-before.sql
"

# 3. Record metrics
ssh akushnir@192.168.168.31 "docker stats --no-stream > /tmp/stats-before.txt"
```

### Post-Implementation Validation

```bash
# 1. Verify replication
ssh akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT count(*) as replication_slots FROM pg_replication_slots;'
"
# Expected: 1

# 2. Check replica lag
ssh akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_time())) as lag_sec;'
"
# Expected: < 1 second

# 3. Verify resource limits applied
ssh akushnir@192.168.168.31 "
  docker inspect code-server-postgres | jq '.[0].HostConfig.Memory'
"
# Expected: 4294967296 (4GB in bytes)

# 4. Check health checks active
ssh akushnir@192.168.168.31 "
  docker ps --format 'table {{.Names}}\t{{.Status}}' | grep healthy | wc -l
"
# Expected: 41
```

---

## Rollback Procedures

### If Replication Fails

```bash
#!/bin/bash

echo "=== REPLICATION ROLLBACK ==="

# 1. Stop replica
ssh akushnir@192.168.168.42 "docker stop code-server-postgres"

# 2. Restore from backup
ssh akushnir@192.168.168.42 "
  docker run --rm \
    -v code-server-enterprise-ops_postgres_data:/data \
    -v /tmp:/backup \
    alpine bash -c 'tar xzf /backup/postgres-backup-*.tar.gz -C /data'
"

# 3. Restart in normal mode (not standby)
ssh akushnir@192.168.168.42 "docker start code-server-postgres"

echo "✓ Rollback complete"
```

### If Resource Limits Cause Issues

```bash
# Temporarily remove limits from specific container
ssh akushnir@192.168.168.31 "
  docker update --memory 0 --cpus 0 code-server-postgres
"
```

---

## Monitoring After Implementation

### Add to Prometheus scrape config

```yaml
scrape_configs:
  - job_name: 'postgres-replication'
    static_configs:
      - targets: ['192.168.168.31:9187', '192.168.168.42:9187']
    
  - job_name: 'docker-metrics'
    static_configs:
      - targets: ['192.168.168.31:9323', '192.168.168.42:9323']
```

### Create alerts

```yaml
groups:
  - name: deployment-gaps
    rules:
      - alert: ReplicationLagTooHigh
        expr: replication_lag_seconds > 5
        for: 5m
        annotations:
          summary: "PostgreSQL replication lag > 5s"
      
      - alert: ContainerResourceLimitExceeded
        expr: container_memory_usage_bytes > container_memory_limit_bytes * 0.9
        for: 5m
        annotations:
          summary: "Container approaching memory limit"
      
      - alert: HealthCheckFailing
        expr: rate(docker_container_health_status{status="unhealthy"}[5m]) > 0
        annotations:
          summary: "Container health check failing"
```

---

## Success Criteria

✓ **Phase 1 Complete:** 
- [ ] Replication slot exists on primary
- [ ] Replica synced and in recovery mode
- [ ] Replication lag < 1 second
- [ ] Both databases identical

✓ **Phase 2 Complete:**
- [ ] All 41 services have memory limits set
- [ ] All 41 services have CPU limits set
- [ ] No container crashes after limits applied

✓ **Phase 3 Complete:**
- [ ] All 41 services passing health checks
- [ ] Health check status visible in docker ps
- [ ] No "unhealthy" containers

✓ **Phase 4-6 Complete:**
- [ ] Orphaned volumes removed (83 → 16-20)
- [ ] Orphaned containers removed
- [ ] Network count normalized (10 → 3 managed)
- [ ] Configuration drift eliminated

---

## Timeline & Ownership

| Phase | Task | Duration | Owner | Deadline |
|-------|------|----------|-------|----------|
| 1 | DB Replication | 30 min | DevOps | May 1 |
| 2 | Resource Limits | 40 min | DevOps | May 1 |
| 3 | Health Checks | 20 min | Platform | May 2 |
| 4-6 | Cleanup & Verify | 60 min | DevOps | May 2 |
| | **Total** | **150 min (2.5 hrs)** | | **May 2** |

---

**Status:** ✓ Ready for Execution  
**Risk Assessment:** Medium (requires data sync, backup available)  
**Approval Required:** Yes (for Phase 1 replication changes)  
**Emergency Rollback:** Available (documented above)
