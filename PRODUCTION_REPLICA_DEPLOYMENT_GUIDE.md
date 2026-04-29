# PRODUCTION REPLICA DEPLOYMENT ARCHITECTURE
# Deploy Identical Services Across 2-Node HA Cluster

**Last Updated:** April 29, 2026  
**Architecture:** 2-Node Active-Active with database replication  
**Status:** Clean production docker-compose ready for deployment

## Architecture Overview

```
┌─────────────────────────────────────┐
│ PRIMARY NODE (192.168.168.31)       │
├─────────────────────────────────────┤
│ PostgreSQL (Primary)  ←──────┐      │
│ Redis (Master)               │      │
│ MongoDB                      │ Replication
│ Elasticsearch                │      │
│ Prometheus                   │      │
│ Grafana                      │      │
│ Loki, Tempo, AlertManager    │      │
│ Caddy (API Gateway)          │      │
│ Microservices (5 services)   │      │
└────────────────────────────────┼────┘
                                 │
                                 │
┌────────────────────────────────┼────┐
│ REPLICA NODE (192.168.168.42)  │    │
├─────────────────────────────────┘    │
│ PostgreSQL (Replica)                 │
│ Redis (Replica via sync)             │
│ MongoDB                              │
│ Elasticsearch                        │
│ Prometheus                           │
│ Grafana                              │
│ Loki, Tempo, AlertManager            │
│ Caddy (API Gateway)                  │
│ Microservices (5 services)           │
└──────────────────────────────────────┘
```

## Deployment Steps

### Step 1: Verify Prerequisites
```bash
# Check nodes are reachable
ssh akushnir@192.168.168.31 "docker --version"
ssh akushnir@192.168.168.42 "docker --version"

# Verify docker-compose availability
ssh akushnir@192.168.168.31 "docker-compose --version"
ssh akushnir@192.168.168.42 "docker-compose --version"
```

### Step 2: Clean Both Nodes
```bash
# PRIMARY
ssh akushnir@192.168.168.31 << 'EOF'
  cd ~/code-server-enterprise-ops
  docker-compose down -v
  docker system prune -af --volumes
EOF

# REPLICA
ssh akushnir@192.168.168.42 << 'EOF'
  cd ~/code-server-enterprise-ops
  docker-compose down -v
  docker system prune -af --volumes
EOF
```

### Step 3: Deploy Production Compose to Both Nodes
```bash
# Copy docker-compose to PRIMARY
scp docker-compose.production-replica.yml \
    akushnir@192.168.168.31:~/code-server-enterprise-ops/docker-compose.yml

# Copy docker-compose to REPLICA
scp docker-compose.production-replica.yml \
    akushnir@192.168.168.42:~/code-server-enterprise-ops/docker-compose.yml

# Sync configuration files to both nodes
rsync -av config/ akushnir@192.168.168.31:~/code-server-enterprise-ops/config/
rsync -av config/ akushnir@192.168.168.42:~/code-server-enterprise-ops/config/

# Sync scripts to both nodes
rsync -av scripts/ akushnir@192.168.168.31:~/code-server-enterprise-ops/scripts/
rsync -av scripts/ akushnir@192.168.168.42:~/code-server-enterprise-ops/scripts/

# Sync certificates to both nodes (if they exist)
rsync -av certs/ akushnir@192.168.168.31:~/code-server-enterprise-ops/certs/
rsync -av certs/ akushnir@192.168.168.42:~/code-server-enterprise-ops/certs/
```

### Step 4: Start Services on Both Nodes
```bash
# PRIMARY - Start services
ssh akushnir@192.168.168.31 << 'EOF'
  cd ~/code-server-enterprise-ops
  docker-compose up -d
  sleep 30
  docker-compose ps
EOF

# REPLICA - Start services  
ssh akushnir@192.168.168.42 << 'EOF'
  cd ~/code-server-enterprise-ops
  docker-compose up -d
  sleep 30
  docker-compose ps
EOF
```

### Step 5: Verify Identical Deployments

```bash
echo "PRIMARY Services:"
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && docker-compose ps"

echo ""
echo "REPLICA Services:"
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && docker-compose ps"

echo ""
echo "Check they match:"
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && docker-compose ps --services | sort" > /tmp/primary-services.txt
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && docker-compose ps --services | sort" > /tmp/replica-services.txt
diff /tmp/primary-services.txt /tmp/replica-services.txt && echo "✅ Identical services" || echo "❌ Services differ"
```

### Step 6: Verify Database Replication

```bash
# Check PostgreSQL replication status on PRIMARY
ssh akushnir@192.168.168.31 << 'EOF'
  docker exec code-server-postgres psql -U postgres -d app_db -c \
    "SELECT client_addr, state, write_lag FROM pg_stat_replication;"
EOF

# Should show replica (192.168.168.42) in streaming state
```

### Step 7: Verify Monitoring Stack

```bash
# Grafana should be accessible
curl -s http://192.168.168.31:3000/api/health | jq '.database'

# Prometheus should be collecting metrics
curl -s http://192.168.168.31:9090/api/v1/query?query=up | jq '.data.result | length'

# AlertManager should be routing alerts
curl -s http://192.168.168.31:9093/api/v1/alerts | jq '.data | length'
```

## Service Breakdown

### Core Infrastructure (Identical on Both Nodes)

| Service | Image | Port | Purpose | Primary | Replica |
|---------|-------|------|---------|---------|---------|
| PostgreSQL | postgres:16-alpine | 5432 | Primary RDBMS | Primary | Replica |
| Redis | redis:7-alpine | 6379 | Cache layer | Master | Synchronized |
| MongoDB | mongo:7.0 | 27017 | Document store | Active | Active |
| Elasticsearch | docker.elastic.co/elasticsearch:8.11.0 | 9200 | Search/Analytics | Active | Active |
| Qdrant | qdrant/qdrant:v1.7.0 | 6333-6334 | Vector DB | Active | Active |

### Observability (Identical on Both Nodes)

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| Prometheus | prom/prometheus:v2.48.0 | 9090 | Metrics collection |
| Grafana | grafana/grafana:10.2.0 | 3000 | Dashboards |
| Loki | grafana/loki:2.9.4 | 3100 | Log aggregation |
| Tempo | grafana/tempo:2.4.1 | 3200-4319 | Distributed tracing |
| AlertManager | prom/alertmanager:v0.27.0 | 9093 | Alert routing |

### API Gateway (Identical on Both Nodes)

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| Caddy | caddy:2.7.4 | 80/443 | Reverse proxy + TLS |

### Microservices (4 Essential Services)

| Service | Port | Purpose | Dependencies |
|---------|------|---------|--------------|
| api-service | 8000 | API server | PostgreSQL, Redis |
| web-service | 3001 | Frontend | api-service |
| user-service | 8001 | User management | PostgreSQL, Redis |
| data-service | 8002 | Data layer | PostgreSQL, MongoDB |
| analytics-service | 8005 | Analytics | PostgreSQL, Elasticsearch |

### Supporting Services

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| pgadmin | dpage/pgadmin4 | 5050 | PostgreSQL management |
| redis-commander | rediscommander/redis-commander | 8081 | Redis management |

## Network Configuration

```yaml
networks:
  code-server-network:
    driver: bridge
    # Services communicate within this bridge network
    # No direct service-to-service exposure needed
```

## Volume Strategy

### Persistent Data (Must be preserved across restarts)

```
postgres_data       → /var/lib/postgresql/data (replicated)
redis_data          → /data (synchronized)
mongodb_data        → /data/db (active-active)
elasticsearch_data  → /usr/share/elasticsearch/data (synced)
qdrant_data         → /qdrant/storage (synced)
prometheus_data     → /prometheus (15-min cleanup)
grafana_data        → /var/lib/grafana (dashboard configs)
loki_data           → /loki (log retention)
tempo_data          → /var/tempo (trace retention)
alertmanager_data   → /alertmanager (alert history)
caddy_data          → /data (SSL certs)
caddy_config        → /config (gateway config)
```

## Database Replication Setup

### PostgreSQL Master-Replica Streaming Replication

**On PRIMARY (192.168.168.31):**
- PostgreSQL runs as PRIMARY
- WAL level set to `replica`
- Max WAL senders: 10
- Max replication slots: 5
- Binary replication logs shipped to REPLICA

**On REPLICA (192.168.168.42):**
- PostgreSQL runs as STANDBY/REPLICA
- Continuous recovery from PRIMARY WAL stream
- Read-only access allowed (hot standby)
- Auto-failover ready via `pg_ctl promote`

**Replication Verification:**
```sql
-- Run on PRIMARY
SELECT client_addr, state, write_lag, flush_lag, replay_lag 
FROM pg_stat_replication;

-- Should show REPLICA connection in 'streaming' state with <1s lag
```

## Failover Procedure

If PRIMARY (192.168.168.31) fails:

1. **Automatic Detection:** Health checks detect node down
2. **Manual Promotion:** On REPLICA, promote to primary:
   ```bash
   ssh akushnir@192.168.168.42
   docker exec code-server-postgres pg_ctl promote -D /var/lib/postgresql/data
   ```
3. **Update API Connections:** Point to REPLICA (192.168.168.42)
4. **Recover PRIMARY:** Once recovered, rejoin as new REPLICA

## Health Checks

All critical services have health checks:

```yaml
postgres:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
    interval: 5s
    retries: 5

redis:
  healthcheck:
    test: ["CMD", "redis-cli", "-a", "${PASSWORD}", "ping"]
    interval: 5s
    retries: 5
```

## Production Readiness Checklist

- [ ] Both nodes have identical docker-compose
- [ ] All configuration files synced to both nodes
- [ ] PostgreSQL replication verified (<1s lag)
- [ ] Redis synchronized across nodes
- [ ] Grafana dashboards accessible on both nodes
- [ ] AlertManager routing to Slack/PagerDuty
- [ ] API Gateway (Caddy) routing to microservices
- [ ] HTTPS certificates mounted and validated
- [ ] All services passing health checks
- [ ] Backup automation configured and running
- [ ] Monitoring dashboards displaying metrics
- [ ] Load balancer pointing to both nodes

## Troubleshooting

### Replication Lag >1s
```bash
# Check PRIMARY PostgreSQL replication status
docker exec code-server-postgres psql -U postgres -c \
  "SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
  
# Check network latency between nodes
ping -c 10 192.168.168.42
```

### Service Not Running on REPLICA
```bash
# Check logs on REPLICA
docker-compose logs service-name

# Compare docker-compose on both nodes
diff <(ssh 192.168.168.31 cat ~/code-server-enterprise-ops/docker-compose.yml) \
     <(ssh 192.168.168.42 cat ~/code-server-enterprise-ops/docker-compose.yml)
```

### Database Connection Issues
```bash
# Test connection to PRIMARY
psql -h 192.168.168.31 -U postgres -d app_db -c "SELECT 1;"

# Test connection to REPLICA
psql -h 192.168.168.42 -U postgres -d app_db -c "SELECT 1;"
```

---

**Status:** Ready for production deployment  
**Last Validated:** April 29, 2026
