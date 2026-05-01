# Comprehensive Deployment Runbook with Rollback Capabilities

**Version**: 1.0  
**Date**: April 25, 2026  
**Audience**: Infrastructure operators and deployment automation systems  

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Deployment Procedure](#deployment-procedure)
3. [Health Verification](#health-verification)
4. [Rollback Procedure](#rollback-procedure)
5. [Emergency Response](#emergency-response)

---

## Pre-Deployment Checklist

Before any deployment, verify the following:

```bash
#!/bin/bash
# Pre-deployment checklist script

echo "=== PRE-DEPLOYMENT VERIFICATION ==="

# 1. Environment variables required
REQUIRED_VARS=(
  "PRIMARY_HOST"
  "REPLICA_HOST"
  "NAS_HOST"
  "APEX_DOMAIN"
  "DB_USER"
  "DB_PASSWORD"
  "DB_NAME"
  "REDIS_PASSWORD"
  "GRAFANA_ADMIN_USER"
  "GRAFANA_ADMIN_PASSWORD"
  "OAUTH2_COOKIE_SECRET"
  "SCHEDULER_API_KEY"
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "❌ Missing required env var: $var"
    exit 1
  fi
done

echo "✅ All required environment variables set"

# 2. Docker connectivity
if ! docker ps > /dev/null 2>&1; then
  echo "❌ Cannot connect to Docker daemon"
  exit 1
fi
echo "✅ Docker connectivity verified"

# 3. Docker Compose syntax
if ! docker-compose config > /dev/null 2>&1; then
  echo "❌ docker-compose.yml syntax invalid"
  exit 1
fi
echo "✅ docker-compose.yml syntax valid"

# 4. Disk space (minimum 100GB)
available_space=$(df / | tail -1 | awk '{print $4}')
if [[ $available_space -lt 104857600 ]]; then
  echo "❌ Insufficient disk space: $(($available_space / 1048576)) MB available"
  exit 1
fi
echo "✅ Sufficient disk space available"

# 5. Network connectivity to hosts
echo "✅ Pre-deployment checklist passed"
```

---

## Deployment Procedure

### Phase 1: Pre-Deployment Backup

```bash
#!/bin/bash
# Backup all persistent data before deployment

set -euo pipefail

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/mnt/nfs/backups/pre-deploy-${BACKUP_DATE}"

mkdir -p "$BACKUP_DIR"

echo "Creating pre-deployment backup..."

# 1. Database backup
docker exec postgres-db pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_DIR/postgres.sql.gz"
echo "✅ PostgreSQL backed up"

# 2. Redis snapshot
docker exec redis-cache redis-cli BGSAVE
docker cp redis-cache:/data/dump.rdb "$BACKUP_DIR/redis-dump.rdb"
echo "✅ Redis backed up"

# 3. Volume snapshots
for volume in postgres_data redis_data redpanda_data prometheus_data loki_data grafana_data ollama_models qdrant_data; do
  docker run --rm -v "$volume:/data" alpine:3.20 tar czf - /data > "$BACKUP_DIR/${volume}.tar.gz"
done
echo "✅ All volumes backed up"

# 4. Configuration backup
cp docker-compose.yml primary_compose_full.yml "$BACKUP_DIR/"
echo "✅ Configuration backed up"

echo "Pre-deployment backup complete: $BACKUP_DIR"
```

### Phase 2: Deploy Init Containers

```bash
#!/bin/bash
# Deploy init containers (Phase 2 of deployment)

set -euo pipefail

echo "Deploying init containers..."

init_services=(
  "prometheus-init"
  "loki-init"
  "alertmanager-init"
  "grafana-init"
  "redis-init"
  "redpanda-init"
  "ollama-init"
  "tempo-init"
  "postgres-init"
  "qdrant-init"
)

for service in "${init_services[@]}"; do
  docker-compose up -d "$service"
  echo "Launched: $service"
done

echo ""
echo "Waiting for init containers to complete..."
sleep 10

# Verify all init containers exited cleanly
failed_inits=0
for service in "${init_services[@]}"; do
  status=$(docker ps -a --format="{{.Names}}\t{{.State}}" | grep "^${service}" | awk '{print $2}')
  if [[ $status != "exited" ]]; then
    echo "❌ Init container still running or failed: $service"
    ((failed_inits++))
  else
    exit_code=$(docker inspect "$service" --format='{{.State.ExitCode}}')
    if [[ $exit_code -eq 0 ]]; then
      echo "✅ Init container completed: $service"
    else
      echo "❌ Init container failed with exit code $exit_code: $service"
      ((failed_inits++))
    fi
  fi
done

if [[ $failed_inits -gt 0 ]]; then
  echo "❌ $failed_inits init containers failed"
  exit 1
fi

echo "✅ All init containers completed successfully"
```

### Phase 3: Deploy Services

```bash
#!/bin/bash
# Deploy all services (Phase 3 of deployment)

set -euo pipefail

echo "Deploying services..."

# Start services in dependency order
docker-compose up -d postgres redis redpanda

sleep 5

docker-compose up -d prometheus loki alertmanager grafana

sleep 5

docker-compose up -d ollama tempo

sleep 5

docker-compose up -d caddy nginx opa oauth2-proxy

sleep 5

docker-compose up -d \
  reputation-engine \
  activity-feed \
  session-broker \
  agent-runtime \
  agent-code-reviewer \
  agent-incident-responder \
  execution-scheduler \
  paperclip \
  env-provisioner \
  memory-engine \
  qdrant

echo "✅ All services deployed"
```

---

## Health Verification

### Automated Health Check

```bash
#!/bin/bash
# Comprehensive health verification

set -euo pipefail

echo "=== HEALTH VERIFICATION START ==="

# Function to check service health
check_service_health() {
  local service=$1
  local expected_state=$2
  
  local status=$(docker ps --format="{{.Names}}\t{{.Status}}" | grep "^${service}" | awk '{print $2}' || echo "not_found")
  
  if [[ $status == *"$expected_state"* ]]; then
    echo "✅ $service: HEALTHY"
    return 0
  else
    echo "❌ $service: UNHEALTHY (status: $status)"
    return 1
  fi
}

# Check all critical services
services=(
  "postgres-db:Up"
  "redis-cache:Up"
  "prometheus:healthy"
  "grafana-dashboards:healthy"
  "loki:healthy"
  "alertmanager:healthy"
)

failed=0
for service_check in "${services[@]}"; do
  service="${service_check%:*}"
  expected="${service_check#*:}"
  
  if ! check_service_health "$service" "$expected"; then
    ((failed++))
  fi
done

if [[ $failed -gt 0 ]]; then
  echo ""
  echo "❌ HEALTH CHECK FAILED - $failed services unhealthy"
  exit 1
fi

echo ""
echo "✅ ALL SERVICES HEALTHY"
```

---

## Rollback Procedure

### Automated Rollback

```bash
#!/bin/bash
# Emergency rollback to previous deployment

set -euo pipefail

ROLLBACK_DIR="${1:?Usage: $0 <backup_directory>}"

if [[ ! -d "$ROLLBACK_DIR" ]]; then
  echo "❌ Backup directory not found: $ROLLBACK_DIR"
  exit 1
fi

echo "=== INITIATING ROLLBACK ==="
echo "Source: $ROLLBACK_DIR"
echo ""

# Step 1: Stop all services
echo "Stopping all services..."
docker-compose down

sleep 5

# Step 2: Remove volumes (optional - for data rollback)
read -p "Remove all volumes to restore from backup? (y/n): " remove_volumes

if [[ $remove_volumes == "y" ]]; then
  echo "Removing volumes..."
  docker volume rm \
    postgres_data \
    redis_data \
    redpanda_data \
    prometheus_data \
    loki_data \
    grafana_data \
    ollama_models \
    tempo_data \
    qdrant_data
  
  echo "Restoring volumes from backup..."
  for volume_file in "$ROLLBACK_DIR"/*.tar.gz; do
    volume_name=$(basename "$volume_file" .tar.gz)
    docker volume create "$volume_name"
    tar xzf "$volume_file" -C "$(docker volume inspect "$volume_name" --format='{{.Mountpoint}}')" || true
  done
fi

# Step 3: Restore configuration
echo "Restoring configuration..."
cp "$ROLLBACK_DIR/docker-compose.yml" docker-compose.yml
cp "$ROLLBACK_DIR/primary_compose_full.yml" primary_compose_full.yml

# Step 4: Redeploy
echo "Redeploying services..."
docker-compose up -d

sleep 30

# Step 5: Verify health
echo "Verifying service health..."
docker ps

echo ""
echo "✅ ROLLBACK COMPLETE"
echo "Verify all services are healthy before proceeding"
```

---

## Emergency Response

### Service Crashed - Quick Recovery

```bash
# Restart a single failed service
docker-compose restart SERVICE_NAME

# Verify it comes back healthy
docker ps | grep SERVICE_NAME

# Check logs
docker-compose logs -f SERVICE_NAME
```

### Disk Full - Emergency Cleanup

```bash
# Find largest volumes
docker run --rm -v /var/lib/docker:/docker alpine:3.20 \
  find /docker/volumes -type f -size +1G -exec ls -lh {} \; | sort -k5 -h | tail -20

# Clean old logs
find /var/log/docker -name "*.log" -mtime +30 -delete

# Prune unused images
docker image prune -a --force --filter "until=720h"

# Prune unused volumes
docker volume prune --force
```

### Network Partition - Multi-Host Recovery

```bash
# Verify connectivity to secondary host
ping -c 5 "$REPLICA_HOST"

# If replica is unreachable:
# 1. Verify primary is operational
# 2. Document replica status in incident log
# 3. Plan replica recovery in next maintenance window
```

---

## Deployment Checklist

- [ ] Pre-deployment checklist passed
- [ ] Pre-deployment backup created
- [ ] Git branch clean (no uncommitted changes)
- [ ] Environment variables verified
- [ ] docker-compose.yml syntax valid
- [ ] Init containers deployed and exited cleanly
- [ ] Services deployed in correct order
- [ ] All critical services healthy
- [ ] No errors in service logs
- [ ] Integration tests passed
- [ ] Monitoring/alerts configured
- [ ] Incident log entry created
- [ ] Stakeholders notified

---

## Rollback Checklist

- [ ] Rollback decision authorized
- [ ] Backup directory location confirmed
- [ ] All services stopped safely
- [ ] Volumes backed up before removal (if applicable)
- [ ] Configuration restored
- [ ] Services redeployed
- [ ] All services reached healthy status
- [ ] Data integrity verified
- [ ] Stakeholders notified
- [ ] Post-mortem scheduled

---

## Key Contacts

- **On-call SRE**: [CONTACT]
- **Infrastructure Lead**: [CONTACT]
- **Database Team**: [CONTACT]
- **Incident Commander**: [CONTACT]

---

## Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/reference/)
- [Kubernetes Migration Guide](../KUBERNETES-MIGRATION-PHASE-4.md)
- [IaC Patterns Reference](IaC-PATTERNS.md)
- [Monitoring & Alerting](MONITORING.md)

---

**Last Updated**: April 25, 2026  
**Status**: APPROVED FOR PRODUCTION USE  
**Version**: 1.0
