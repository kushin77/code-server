# Phase 2: Resource Limits Configuration - Implementation Guide

**Date**: April 26, 2026  
**Phase**: 2 of 4  
**Duration**: 3-4 hours  
**Effort Level**: High (configuration changes across 20 services)  
**Risk Level**: Medium (testing required, but rollback available)  

---

## Overview

Phase 2 applies resource limit configurations to docker-compose services based on Phase 1 profiling findings. All configurations are applied incrementally with testing between stages.

---

## Implementation Strategy

### Stage Sequence
1. **Stage 1**: Infrastructure Services (PostgreSQL, Redis, Redpanda) - 1-2 hours
2. **Stage 2**: Data Services (Qdrant, Scheduler) - 30 minutes
3. **Stage 3**: API Services (edge-agent, paperclip-api, etc.) - 1 hour
4. **Stage 4**: Observability (prometheus, grafana, loki) - 30 minutes

### Quality Assurance Process
- **Before Stage**: Backup docker-compose.yml
- **During Stage**: Apply limits incrementally
- **After Each Service**: Verify health via `docker-compose ps`
- **Between Stages**: Review logs for errors
- **After Stage**: Full health check (connectivity tests)

---

## Stage 1: Infrastructure Services (1-2 hours)

### Services in Stage 1
1. PostgreSQL (database)
2. Redis (cache)
3. Redpanda (message broker)
4. PgBouncer (connection pool)

### Configuration Template

```yaml
# PostgreSQL - Database core
postgres:
  deploy:
    resources:
      limits:
        cpus: "4"
        memory: 8G
      reservations:
        cpus: "2"
        memory: 4G

# Redis - Cache layer
redis:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 4G
      reservations:
        cpus: "1"
        memory: 2G

# Redpanda - Message broker
redpanda:
  deploy:
    resources:
      limits:
        cpus: "4"
        memory: 4G
      reservations:
        cpus: "2"
        memory: 2G

# PgBouncer - Connection pool
pgbouncer:
  deploy:
    resources:
      limits:
        cpus: "1"
        memory: 512m
      reservations:
        cpus: "0.5"
        memory: 256m
```

### Validation Checklist
- [ ] All 4 services start successfully
- [ ] PostgreSQL accepts connections
- [ ] Redis responds to PING
- [ ] Redpanda broker is healthy
- [ ] PgBouncer pool is active
- [ ] No OOMKilled events
- [ ] CPU usage remains <50%

### Commands for Stage 1

```bash
# Backup before changes
cp docker-compose.yml docker-compose.yml.backup-stage1

# Update services in Stage 1
# (Edit docker-compose.yml with configurations above)

# Restart services
docker-compose up -d postgres redis redpanda pgbouncer

# Verify health
docker-compose ps | grep "postgres\|redis\|redpanda\|pgbouncer"

# Check for errors
docker-compose logs postgres | tail -20
docker-compose logs redis | tail -20
docker-compose logs redpanda | tail -20

# Test connectivity
docker-compose exec postgres psql -U postgres -c "SELECT 1"
docker-compose exec redis redis-cli ping
```

---

## Stage 2: Data Services (30 minutes)

### Services in Stage 2
1. Qdrant (vector database)
2. Temporal Server (orchestration)
3. Scheduler (data processing)

### Configuration Template

```yaml
# Qdrant - Vector database
qdrant:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 4G
      reservations:
        cpus: "1"
        memory: 2G

# Temporal Server - Workflow orchestration
temporal-server:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 2G
      reservations:
        cpus: "1"
        memory: 1G

# Scheduler - Data processing
scheduler:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 2G
      reservations:
        cpus: "1"
        memory: 1G
```

### Validation Checklist
- [ ] Qdrant accepts vector operations
- [ ] Temporal Server workflow store is accessible
- [ ] Scheduler processes tasks successfully
- [ ] No resource contention observed

### Commands for Stage 2

```bash
# Backup before changes
cp docker-compose.yml docker-compose.yml.backup-stage2

# Update Stage 2 services (edit docker-compose.yml)

# Restart Stage 2 services
docker-compose up -d qdrant temporal-server scheduler

# Verify health
docker-compose ps | grep "qdrant\|temporal\|scheduler"

# Check logs
docker-compose logs qdrant | tail -10
```

---

## Stage 3: API Services (1 hour)

### Services in Stage 3
1. Edge Agent
2. Paperclip API
3. Paperclip SaaS API
4. Execution Scheduler

### Configuration Template

```yaml
# Edge Agent
edge-agent:
  deploy:
    resources:
      limits:
        cpus: "1"
        memory: 512m
      reservations:
        cpus: "0.5"
        memory: 256m

# Paperclip API
paperclip-api:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 2G
      reservations:
        cpus: "1"
        memory: 1G

# Paperclip SaaS API
paperclip-saas-api:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 2G
      reservations:
        cpus: "1"
        memory: 1G

# Execution Scheduler
execution-scheduler:
  deploy:
    resources:
      limits:
        cpus: "1"
        memory: 1G
      reservations:
        cpus: "0.5"
        memory: 512m
```

### Validation Checklist
- [ ] All API services respond to health checks
- [ ] Edge agent connects to primary
- [ ] API endpoints are accessible
- [ ] Response times acceptable

---

## Stage 4: Observability Services (30 minutes)

### Services in Stage 4
1. Prometheus (metrics collection)
2. Grafana (visualization)
3. Loki (log aggregation)
4. Promtail (log shipping)

### Configuration Template

```yaml
# Prometheus
prometheus:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 2G
      reservations:
        cpus: "1"
        memory: 1G

# Grafana
grafana:
  deploy:
    resources:
      limits:
        cpus: "1"
        memory: 512m
      reservations:
        cpus: "0.5"
        memory: 256m

# Loki
loki:
  deploy:
    resources:
      limits:
        cpus: "2"
        memory: 1G
      reservations:
        cpus: "1"
        memory: 512m

# Promtail
promtail:
  deploy:
    resources:
      limits:
        cpus: "1"
        memory: 256m
      reservations:
        cpus: "0.5"
        memory: 128m
```

### Validation Checklist
- [ ] Prometheus scrapes targets successfully
- [ ] Grafana dashboards display metrics
- [ ] Loki receives logs from Promtail
- [ ] No alert storms triggered

---

## Rollback Procedures

### If Stage Fails
```bash
# Immediate rollback
cp docker-compose.yml.backup-stage<N> docker-compose.yml
docker-compose down
docker-compose up -d

# Verify restoration
docker-compose ps
```

### Progressive Rollback
```bash
# If specific service fails, isolate by removing its limits
docker-compose up -d <service-name>
```

---

## Performance Validation

### After Each Stage - Run Tests

```bash
# CPU and memory check
docker stats --no-stream

# API connectivity test
curl http://localhost:3100/api/health

# Database query test
docker-compose exec postgres psql -U postgres -d paperclip -c "SELECT COUNT(*) FROM users;"

# Message broker test
docker-compose exec redpanda rpk topic list

# Monitoring test
curl http://localhost:9090/api/v1/status/config
```

---

## Phase 2 Completion Checklist

- [ ] Stage 1 (Infrastructure) deployed successfully
- [ ] Stage 2 (Data Services) deployed successfully
- [ ] Stage 3 (API Services) deployed successfully
- [ ] Stage 4 (Observability) deployed successfully
- [ ] All 20 services have resource limits defined
- [ ] No OOMKilled events in logs
- [ ] No persistent errors observed
- [ ] Compliance increase from 60% to 70%
- [ ] Ready for Phase 3 validation

---

## Expected Outcomes

✅ **After Phase 2**:
- All 20 services configured with resource limits
- Docker-compose.yml updated with deploy resources sections
- Backup files retained for rollback if needed
- System running with resource constraints enforced
- Compliance Score: 70/100 (+10 points)
- Q3 Readiness: 80%

---

## Execution Timeline

**Phase 2 Start**: Ready to begin  
**Stage 1**: 1-2 hours (infrastructure)  
**Stage 2**: 30 minutes (data services)  
**Stage 3**: 1 hour (API services)  
**Stage 4**: 30 minutes (observability)  
**Total**: 3-4 hours  

**Expected Completion**: Within 4 hours of start

---

## Next Steps

After Phase 2 completion:
1. **Phase 3**: Validation & Testing (2-3 hours)
2. **Phase 4**: Monitoring Setup (1-2 hours)

---

**Phase 2 Status**: Ready to Execute
**Estimated Completion**: +3-4 hours from start

