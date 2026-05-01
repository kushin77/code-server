# Phase 6: Application Configuration & High Availability

**Target Completion**: April 29-30, 2026  
**Goal**: Full platform deployment with HA, replication, and operational excellence  
**Success Criteria**: All 40+ services deployed, replica synchronized, observability active  

---

## Phase 6 Overview

Following Phase 5 infrastructure deployment, Phase 6 focuses on:
1. **Application Configuration** - Resolve missing .env blockers
2. **Service Recovery** - Complete deployment of all 40+ services
3. **High Availability** - Replica host deployment and synchronization
4. **Observability** - Full metrics, logging, and alerting
5. **Operational Excellence** - Automated scaling, failover, disaster recovery

---

## Work Packages

### WP-6.1: Environment Configuration (BLOCKER RESOLUTION)

**Objective**: Create production environment configuration for all services

**Status**: 🔴 BLOCKED
- Current Issue: Application services crash due to missing .env file
- Impact: execution-scheduler, reputation-engine, memory-engine cannot start

**Tasks**:

#### 6.1.1 Create Production .env File (Local Only)
Note: Create this file locally and do not commit it to git.
```
# Database Configuration
DATABASE_URL=postgresql://postgres:password@code-server-postgres:5432/code_server
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=40

# Cache Configuration  
REDIS_URL=redis://code-server-redis:6379/0
REDIS_PASSWORD=
REDIS_SENTINEL_NODES=code-server-redis-sentinel-primary:26379

# Message Queue
KAFKA_BROKER=code-server-redpanda:9092
KAFKA_TOPIC_PREFIX=code-server.

# AI/ML Services
OLLAMA_URL=http://code-server-ollama:11434
OLLAMA_MODEL=llama2:7b
QDRANT_HOST=code-server-qdrant
QDRANT_PORT=6333

# API Configuration
SCHEDULER_API_KEY=<generate-secure-key>
REPUTATION_ENGINE_API_KEY=<generate-secure-key>
ACTIVITY_FEED_API_KEY=<generate-secure-key>

# OPA Policy Engine
OPA_URL=http://code-server-opa:8181
OPA_POLICY_BUNDLE=code-server-policies

# Observability
PROMETHEUS_URL=http://code-server-prometheus:9090
GRAFANA_URL=http://code-server-grafana:3000
LOKI_URL=http://code-server-loki:3100

# Security
OAUTH2_CLIENT_ID=<from-auth-provider>
OAUTH2_CLIENT_SECRET=<from-auth-provider>
OAUTH2_REDIRECT_URI=https://ops.kushnir.cloud/oauth2/callback
```

#### 6.1.2 Generate API Keys
- [ ] SCHEDULER_API_KEY (32 chars, alphanumeric)
- [ ] REPUTATION_ENGINE_API_KEY (32 chars, alphanumeric)
- [ ] ACTIVITY_FEED_API_KEY (32 chars, alphanumeric)
- [ ] Store in secure vault (sealed in Phase 7)

#### 6.1.3 Deploy .env to Primary Host
```bash
scp .env akushnir@192.168.168.31:~/code-server-enterprise-ops/

# Verify
ssh akushnir@192.168.168.31 "ls -la ~/code-server-enterprise-ops/.env"
```

#### 6.1.4 Verify .env Loading
```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker-compose config | grep -A 5 'SCHEDULER_API_KEY\|DATABASE_URL'"
```

---

### WP-6.2: Application Service Deployment

**Objective**: Deploy all 40+ services with correct configuration

**Status**: 🟡 IN PROGRESS
- Current Deployed: 15 services (infrastructure + legacy)
- Target: 40+ services (all profiles)
- Blocker: Waiting for .env from WP-6.1

**Tasks**:

#### 6.2.1 Deploy with All Profiles
```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker-compose -f docker-compose.deploy.yml \
    --profile ai \
    --profile governance \
    --profile infrastructure \
    --profile observability \
    --profile agents \
    up -d --force-recreate 2>&1 | tee deploy.log"
```

#### 6.2.2 Verify Service Startup (10-minute window)
```bash
# Check every 10 seconds
for i in {1..60}; do
  ssh akushnir@192.168.168.31 \
    "docker ps --format '{{.Names}}\t{{.Status}}' | grep -c 'healthy\\|running'" && \
  sleep 10
done

# Expected progression:
# t=0s:  15 containers (infrastructure)
# t=60s: 25+ containers (services starting)
# t=300s: 40+ containers (all operational)
```

#### 6.2.3 Check Service Health
```bash
ssh akushnir@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}' | \
  tail -n +2 | \
  awk '{print $NF}' | \
  sort | uniq -c"

# Expected output:
# 5 exited
# 35 Up X minutes
# 10 (healthy)
```

#### 6.2.4 Troubleshoot Failing Services
```bash
# View logs of services in crash loop
ssh akushnir@192.168.168.31 "for svc in execution-scheduler reputation-engine memory-engine; do \
  echo \"=== \$svc ===\"  && \
  docker logs code-server-\$svc --tail=10 2>&1 | grep -E 'error|ERROR|Exception' || echo 'no errors'; \
done"
```

---

### WP-6.3: Replica Host Deployment (HA)

**Objective**: Deploy complete stack to replica host with active-active sync

**Status**: 🔴 NOT STARTED
- Target: 192.168.168.42
- Mode: Active-Active replication
- Sync: Redis + PostgreSQL streaming

**Tasks**:

#### 6.3.1 Prepare Replica Host
```bash
ssh akushnir@192.168.168.42 "mkdir -p ~/code-server-enterprise-ops && ls -la"
```

#### 6.3.2 Copy Deployment Files to Replica
```bash
scp docker-compose.deploy.yml akushnir@192.168.168.42:~/code-server-enterprise-ops/
scp docker-compose.override.yml akushnir@192.168.168.42:~/code-server-enterprise-ops/
scp .env akushnir@192.168.168.42:~/code-server-enterprise-ops/
```

#### 6.3.3 Deploy to Replica with Replication Mode
```bash
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  REPLICATION_MODE=replica \
  REPLICA_OF_PRIMARY=192.168.168.31 \
  docker-compose -f docker-compose.deploy.yml up -d"
```

#### 6.3.4 Verify Replication
```bash
# Check PostgreSQL replication
ssh akushnir@192.168.168.31 "docker exec code-server-postgres psql -U postgres -c '\
  SELECT slot_name, restart_lsn FROM pg_replication_slots;'"

# Check Redis replication
ssh akushnir@192.168.168.42 "docker exec code-server-redis redis-cli INFO replication"

# Expected:
# role:slave
# master_host:192.168.168.31
# master_port:6379
# master_link_status:up
```

#### 6.3.5 Test Failover (NO DOWNTIME)
```bash
# Promote replica
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  REPLICATION_MODE=primary docker-compose -f docker-compose.deploy.yml restart"

# Verify replica is now accepting writes
ssh akushnir@192.168.168.42 "docker exec code-server-redis redis-cli SET test-key 'failover-test'"
```

---

### WP-6.4: Observability & Monitoring

**Objective**: Configure complete observability stack for operational visibility

**Status**: 🟡 PARTIAL
- Loki: ✅ Running
- Prometheus: ⏳ Needs configuration
- Grafana: ⏳ Needs dashboards
- AlertManager: ⏳ Needs alert rules

**Tasks**:

#### 6.4.1 Configure Prometheus Scrape Targets
```yaml
# prometheus-config.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'code-server-platform'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'postgres-metrics'
    static_configs:
      - targets: ['code-server-postgres-exporter:9187']
      
  - job_name: 'redis-metrics'
    static_configs:
      - targets: ['code-server-redis-exporter:9121']
      
  - job_name: 'application-services'
    service_discovery_mode: 'docker'
    docker_sd_config:
      host: unix:///var/run/docker.sock
```

#### 6.4.2 Deploy Prometheus Configuration
```bash
scp prometheus-config.yml akushnir@192.168.168.31:~/code-server-enterprise-ops/config/prometheus/

ssh akushnir@192.168.168.31 "docker exec code-server-prometheus \
  kill -HUP 1  # Reload configuration"
```

#### 6.4.3 Create Grafana Dashboards
```bash
# Via API:
curl -X POST http://192.168.168.31:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboard-platform-overview.json

curl -X POST http://192.168.168.31:3000/api/dashboards/db \
  -d @dashboard-services.json

curl -X POST http://192.168.168.31:3000/api/dashboards/db \
  -d @dashboard-infrastructure.json
```

#### 6.4.4 Configure AlertManager Rules
```yaml
# alertmanager-rules.yml
groups:
  - name: platform-alerts
    interval: 30s
    rules:
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes{container_name=~"code-server-.*"} > 1e9
        for: 2m
        annotations:
          summary: "High memory usage in {{ $labels.container_name }}"
          
      - alert: DatabaseConnectionPoolExhausted
        expr: pg_stat_connections > 180
        for: 1m
        annotations:
          summary: "PostgreSQL connection pool nearly exhausted"
          
      - alert: RedisKeyEvictions
        expr: redis_evicted_keys_total > 0
        for: 1m
        annotations:
          summary: "Redis is evicting keys (memory pressure)"
```

---

### WP-6.5: Horizontal Scaling & Load Balancing

**Objective**: Configure service scaling and load distribution

**Status**: 🔴 NOT STARTED
- Load Balancer: Caddy (to be configured)
- Autoscaling: Docker service mode (to be configured)
- Metrics-driven: Depends on Prometheus (WP-6.4)

**Tasks**:

#### 6.5.1 Configure Caddy Load Balancer
```
# Caddyfile
{
  admin 0.0.0.0:2019
  log {
    output stdout
    format json
  }
}

# API Load Balancing
api.kushnir.cloud {
  encode gzip
  
  # Reverse proxy with health checks
  reverse_proxy localhost:8000 localhost:8001 localhost:8002 {
    health_uri /health
    health_interval 10s
    
    policy least_conn  # Load balance by connection count
    
    # Timeouts
    timeout 30s
    dial_timeout 5s
  }
}

# Metrics Endpoint (Prometheus scraping)
metrics.kushnir.cloud {
  reverse_proxy localhost:9090
}
```

#### 6.5.2 Deploy Multiple Service Instances
```bash
# Create docker-compose scale file
cat > docker-compose.scale.yml <<EOF
version: '3.8'
services:
  execution-scheduler:
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        
  activity-feed:
    deploy:
      replicas: 2
      
  reputation-engine:
    deploy:
      replicas: 2
EOF

# Deploy with scaling
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker-compose -f docker-compose.deploy.yml \
                 -f docker-compose.scale.yml up -d"
```

#### 6.5.3 Configure Autoscaling Policies
```yaml
# kubernetes-like policy (using Orbiter or similar)
scaling_policies:
  - name: cpu-scaling
    metric: container_cpu_usage_seconds_total
    target: 70%  # Scale up if >70%
    threshold: 80%  # Hard limit at 80%
    min_replicas: 1
    max_replicas: 5
    scale_up_cooldown: 60s
    scale_down_cooldown: 300s
```

---

### WP-6.6: Disaster Recovery & Backup

**Objective**: Implement automated backup and recovery procedures

**Status**: 🔴 NOT STARTED
- Database Backups: Automated daily
- Configuration Backups: NAS mirroring
- Recovery Testing: Monthly drills

**Tasks**:

#### 6.6.1 Configure Database Backups
```bash
# PostgreSQL backup script
cat > backup-postgres.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/nas/backups/postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

docker exec code-server-postgres pg_dump -U postgres code_server | \
  gzip > "${BACKUP_DIR}/postgres-${TIMESTAMP}.sql.gz"

# Keep only last 30 days
find "${BACKUP_DIR}" -name "postgres-*.sql.gz" -mtime +30 -delete
EOF

chmod +x backup-postgres.sh
```

#### 6.6.2 Schedule Backup Cron Job
```bash
# Add to crontab
0 2 * * * /home/akushnir/code-server/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1
0 3 * * * /home/akushnir/code-server/backup-redis.sh >> /var/log/redis-backup.log 2>&1
```

#### 6.6.3 Test Restore Procedure
```bash
# Monthly recovery drill
# 1. Stop services
ssh akushnir@192.168.168.31 "docker-compose -f docker-compose.deploy.yml down"

# 2. Restore from backup
ssh akushnir@192.168.168.31 "docker exec code-server-postgres \
  psql -U postgres < /mnt/nas/backups/postgres/latest-backup.sql"

# 3. Verify recovery
ssh akushnir@192.168.168.31 "docker exec code-server-postgres \
  psql -U postgres -c 'SELECT COUNT(*) FROM users;'"

# 4. Restart services
ssh akushnir@192.168.168.31 "docker-compose -f docker-compose.deploy.yml up -d"
```

---

### WP-6.7: Operational Runbooks

**Objective**: Document all operational procedures for ops team

**Status**: 🟡 PARTIAL
- Phase 5 handoff completed
- Phase 6 procedures to be added

**Tasks**:

#### 6.7.1 Create Runbooks
- [ ] Service health check procedure
- [ ] Common troubleshooting guide
- [ ] Emergency shutdown procedure
- [ ] Emergency recovery procedure
- [ ] Adding new services
- [ ] Scaling service up/down

#### 6.7.2 Document Common Issues
- [ ] Service crashes on startup
- [ ] Database connection pool exhaustion
- [ ] Redis memory pressure
- [ ] Network partition handling
- [ ] Disk space issues

#### 6.7.3 Create On-Call Procedures
- [ ] Incident response workflow
- [ ] Escalation paths
- [ ] Approval requirements
- [ ] Communication procedures

---

## Success Metrics

| Metric | Target | Current | Phase 6 Goal |
|--------|--------|---------|-------------|
| Services Deployed | 40+ | 15 | 40+ ✅ |
| Services Healthy | >95% | 7/15 | 38/40 ✅ |
| HA Replica Synced | Yes | No | Yes ✅ |
| Observability | Full | Partial | Complete ✅ |
| Autoscaling | Active | N/A | Active ✅ |
| Backup Coverage | 100% | 0% | 100% ✅ |
| Recovery Time (RTO) | <5min | N/A | <5min ✅ |
| Failover Test | Pass | N/A | Pass ✅ |

---

## Timeline & Dependencies

```
┌─ WP-6.1 (Environment Config) ─────────────┐
│                                            │
├─→ WP-6.2 (Application Deploy) ─────┐      │
│                                    │      │
├─→ WP-6.3 (Replica Deployment) ◄───┤──────┤
│        (Depends on 6.2)            │      │
│                                    │      │
├─→ WP-6.4 (Observability) ◄────────┤──────┤
│     (Depends on 6.2)               │      │
│                                    │      │
├─→ WP-6.5 (Scaling) ────────────────┤──────┤
│     (Depends on 6.4)               │      │
│                                    │      │
└─→ WP-6.6 (Disaster Recovery) ◄─────┴──────┘
└─→ WP-6.7 (Runbooks)
```

**Critical Path**:
1. WP-6.1 (Config) → 30 min
2. WP-6.2 (Deploy) → 10 min (+ 5 min startup)
3. WP-6.3 (Replica) → 10 min (+ 5 min startup)
4. WP-6.4 (Observability) → 30 min
5. WP-6.5 (Scaling) → 20 min
6. WP-6.6 (DR) → 45 min
7. WP-6.7 (Runbooks) → 60 min

**Total Estimated**: ~3 hours (with 15 min startup windows)

---

## Phase 6 Completion Criteria

### Must Have (Blocking)
- [ ] All 40+ services deployed and healthy
- [ ] Replica host synchronized with primary
- [ ] Failover tested and confirmed working
- [ ] Prometheus collecting metrics from all services
- [ ] AlertManager configured with at least 5 alert rules

### Should Have (High Priority)
- [ ] Grafana dashboards for platform overview
- [ ] Horizontal scaling tested (2x instances of core service)
- [ ] Daily backup cron jobs configured
- [ ] Recovery procedure documented and tested

### Nice to Have (Low Priority)
- [ ] Autoscaling policies refined based on load testing
- [ ] Multi-region failover configured
- [ ] Cost optimization implemented
- [ ] Custom metrics added to Prometheus

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Service config validation fails | Medium | High | Pre-validate schema in WP-6.1 |
| Database replication sync fails | Low | High | Test with dry-run first |
| Network partition during failover | Low | High | Implement split-brain detection |
| Disk space exhausted | Medium | Medium | Implement retention policies |
| Certificate expiry on TLS gateway | Low | High | Implement automated renewal |

---

## Phase 6 Handoff Readiness

**When Phase 6 is complete**, operations team will have:
- ✅ Complete infrastructure deployment (primary + replica)
- ✅ 40+ services running with health checks active
- ✅ Full observability (metrics, logs, traces)
- ✅ Automated failover capability
- ✅ Horizontal scaling configured
- ✅ Daily backups configured
- ✅ Recovery procedures tested
- ✅ Comprehensive runbooks

**Transition to Phase 7**: Cost Optimization & Performance Tuning
- [ ] Resource allocation optimization
- [ ] Database query optimization
- [ ] Cache hit ratio improvement
- [ ] Network latency reduction
- [ ] Disk I/O optimization

---

**Phase 6 Assigned**: April 29, 2026  
**Status**: READY TO START  
**Next Milestone**: Phase 6 Completion (April 30, 2026)  
