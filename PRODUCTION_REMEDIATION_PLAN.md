# PRODUCTION DEPLOYMENT REMEDIATION PLAN
## Fixing the Loose Container Problem

**Issue:** Current deployment has loose placeholder containers and non-identical replicas  
**Root Cause:** Ad-hoc docker-compose configurations without proper architecture  
**Solution:** Deploy clean, production-grade, IDENTICAL services to both nodes  

---

## Current State Problems

❌ **PRIMARY (192.168.168.31):**
- Has: redpanda-console, grafana, redis, opa, caddy, user-service, etc.
- Missing: PostgreSQL, Prometheus, Loki, Tempo, Redpanda, API service
- Total: 19 containers

❌ **REPLICA (192.168.168.42):**
- Has: nginx, minio, api-service, prometheus, postgres, etc.
- Missing: OPA, Caddy, many microservices
- Total: 20 containers

❌ **Both nodes:**
- No common, essential services (NOT a true replica)
- Different database locations
- Incomplete monitoring stack
- Missing database replication
- No API gateway on PRIMARY
- No coordinated failover capability

---

## Fix: Production Replica Architecture

### What Should Be Deployed (IDENTICAL on Both Nodes)

**MUST HAVE on Both Nodes:**
1. PostgreSQL (PRIMARY on 192.168.168.31, REPLICA on 192.168.168.42)
2. Redis (synchronized)
3. MongoDB
4. Elasticsearch
5. Qdrant (vector DB)
6. Prometheus (metrics)
7. Grafana (dashboards)
8. Loki (logs)
9. Tempo (tracing)
10. AlertManager
11. Caddy (reverse proxy/API gateway)
12. Core microservices (API, Web, User, Data, Analytics)

**Supporting:**
- PgAdmin (DB management)
- Redis Commander (cache management)

**SHOULD NOT HAVE (the loose/dummy containers):**
- ❌ `code-server-c-1` through `code-server-c-26` (placeholder alpine containers)
- ❌ Random standalone services
- ❌ Ollama (not in production spec)
- ❌ Redpanda console without Redpanda
- ❌ Registry without push/pull pipeline

---

## Remediation Steps

### Phase 1: Validation (10 minutes)

```bash
# 1. Verify node connectivity
ping -c 1 192.168.168.31 && echo "✅ PRIMARY"
ping -c 1 192.168.168.42 && echo "✅ REPLICA"

# 2. Check Docker availability
ssh akushnir@192.168.168.31 "docker ps | wc -l"
ssh akushnir@192.168.168.42 "docker ps | wc -l"

# 3. Check storage space
ssh akushnir@192.168.168.31 "df -h / | tail -1 | awk '{print $4}'"
ssh akushnir@192.168.168.42 "df -h / | tail -1 | awk '{print $4}'"
```

### Phase 2: Cleanup (15 minutes)

**PRIMARY Node:**
```bash
ssh akushnir@192.168.168.31 << 'EOF'
cd ~/code-server-enterprise-ops

# Stop all containers
docker-compose down || true

# Remove all dangling images, volumes, networks
docker system prune -af --volumes

# Clear docker directory
rm -rf /var/lib/docker/volumes/*

# Verify cleanup
docker ps
docker images
docker volume ls
EOF
```

**REPLICA Node:**
```bash
ssh akushnir@192.168.168.42 << 'EOF'
cd ~/code-server-enterprise-ops

# Stop all containers
docker-compose down || true

# Remove all dangling images, volumes, networks
docker system prune -af --volumes

# Clear docker directory
rm -rf /var/lib/docker/volumes/*

# Verify cleanup
docker ps
docker images
docker volume ls
EOF
```

### Phase 3: Deploy Clean Compose (20 minutes)

```bash
# Verify clean docker-compose exists locally
ls -la docker-compose.production-replica.yml

# Deploy to PRIMARY
scp docker-compose.production-replica.yml \
    akushnir@192.168.168.31:~/code-server-enterprise-ops/docker-compose.yml

# Deploy to REPLICA
scp docker-compose.production-replica.yml \
    akushnir@192.168.168.42:~/code-server-enterprise-ops/docker-compose.yml

# Start services on PRIMARY
ssh akushnir@192.168.168.31 << 'EOF'
cd ~/code-server-enterprise-ops
docker-compose pull
docker-compose up -d
sleep 30
docker-compose ps
EOF

# Start services on REPLICA
ssh akushnir@192.168.168.42 << 'EOF'
cd ~/code-server-enterprise-ops
docker-compose pull
docker-compose up -d
sleep 30
docker-compose ps
EOF
```

### Phase 4: Verification (20 minutes)

```bash
# Get service list from PRIMARY
PRIMARY_SERVICES=$(ssh akushnir@192.168.168.31 \
  "cd ~/code-server-enterprise-ops && docker-compose ps --services | sort")

# Get service list from REPLICA
REPLICA_SERVICES=$(ssh akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise-ops && docker-compose ps --services | sort")

# Compare
if [ "$PRIMARY_SERVICES" = "$REPLICA_SERVICES" ]; then
  echo "✅ IDENTICAL: Both nodes have the same services"
  echo "$PRIMARY_SERVICES" | head -15
else
  echo "❌ MISMATCH: Services differ between nodes"
  echo "PRIMARY unique:"
  comm -23 <(echo "$PRIMARY_SERVICES") <(echo "$REPLICA_SERVICES")
  echo "REPLICA unique:"
  comm -13 <(echo "$PRIMARY_SERVICES") <(echo "$REPLICA_SERVICES")
fi
```

### Phase 5: Database Replication Setup (10 minutes)

```bash
# Wait for PostgreSQL to be healthy on both nodes
sleep 30

# On PRIMARY, initialize replication
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-postgres psql -U postgres -d postgres -c \
  "CREATE ROLE replication_user WITH REPLICATION LOGIN PASSWORD 'replication_password_secure';"
EOF

# On REPLICA, connect to PRIMARY's WAL stream
ssh akushnir@192.168.168.42 << 'EOF'
docker exec code-server-postgres pg_basebackup \
  -h 192.168.168.31 \
  -D /var/lib/postgresql/data/replica \
  -U replication_user \
  -v -P
EOF

# Verify replication status
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-postgres psql -U postgres -c \
  "SELECT client_addr, state, write_lag FROM pg_stat_replication;"
EOF
```

### Phase 6: Monitoring Verification (10 minutes)

```bash
# Check Grafana is accessible
curl -s -o /dev/null -w "%{http_code}" http://192.168.168.31:3000/api/health
curl -s -o /dev/null -w "%{http_code}" http://192.168.168.42:3000/api/health

# Check Prometheus is collecting
curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length'
curl -s http://192.168.168.42:9090/api/v1/targets | jq '.data.activeTargets | length'

# Check AlertManager is working
curl -s http://192.168.168.31:9093/api/v1/status | jq '.data'
```

### Phase 7: API Gateway Test (10 minutes)

```bash
# Test Caddy is routing correctly
curl -s http://192.168.168.31/health
curl -s http://192.168.168.31/api/v1/health
curl -s http://192.168.168.42/health

# Check HTTPS is ready (certificates should be present)
ls -la certs/
curl --insecure -I https://192.168.168.31/
```

---

## Expected Result After Remediation

✅ **PRIMARY (192.168.168.31):**
```
code-server-postgres          Up
code-server-redis             Up (healthy)
code-server-mongodb           Up (healthy)
code-server-elasticsearch     Up (healthy)
code-server-qdrant            Up
code-server-prometheus        Up
code-server-grafana           Up
code-server-loki              Up
code-server-tempo             Up
code-server-alertmanager      Up
code-server-caddy             Up
code-server-api-service       Up
code-server-web-service       Up
code-server-user-service      Up
code-server-data-service      Up
code-server-analytics-service Up
code-server-pgadmin           Up
code-server-redis-commander   Up
────────────────────────────────────
TOTAL: 18 essential services (production-grade)
```

✅ **REPLICA (192.168.168.42):**
```
[IDENTICAL TO PRIMARY]
TOTAL: 18 essential services (production-grade)
```

✅ **Characteristics:**
- Database replication: PRIMARY → REPLICA (<1s lag)
- API Gateway: Both nodes routing to microservices
- Monitoring: 2,000+ metrics collected on both
- Health checks: All 18 services passing
- Failover ready: REPLICA can promote to PRIMARY instantly
- HA Status: True active-active with database streaming replication

---

## Timeline

| Phase | Task | Duration | Status |
|-------|------|----------|--------|
| 1 | Validation | 10 min | Ready |
| 2 | Cleanup | 15 min | Ready |
| 3 | Deploy | 20 min | Ready |
| 4 | Verify | 20 min | Ready |
| 5 | Replication | 10 min | Ready |
| 6 | Monitoring | 10 min | Ready |
| 7 | API Gateway | 10 min | Ready |
| **TOTAL** | **Full Fix** | **95 min (~1.5 hours)** | ✅ |

---

## Success Criteria

✅ **Infrastructure:**
- [ ] Both nodes have identical docker-compose
- [ ] 18 services running on each node
- [ ] No loose/placeholder containers
- [ ] All services pass health checks

✅ **Replication:**
- [ ] PostgreSQL replication lag <1 second
- [ ] REPLICA synced to PRIMARY
- [ ] Failover procedure tested

✅ **Monitoring:**
- [ ] Prometheus collecting 2,000+ metrics
- [ ] Grafana dashboards accessible
- [ ] AlertManager routing alerts
- [ ] Loki aggregating logs
- [ ] Tempo collecting traces

✅ **API Gateway:**
- [ ] Caddy routing to all 5 microservices
- [ ] HTTP (port 80) operational
- [ ] HTTPS (port 443) ready
- [ ] Health endpoints responding

✅ **Production Readiness:**
- [ ] No container crashes in last 5 minutes
- [ ] <2% error rate on metrics
- [ ] All volumes persistent and mounted
- [ ] Network latency <10ms between nodes

---

**Status:** Remediation plan ready for execution  
**Implementation Time:** ~95 minutes  
**Expected Outcome:** Production-grade HA cluster with identical replicas
