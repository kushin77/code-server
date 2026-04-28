# Quick Reference: Cluster Naming & VIP

## Container Naming Convention

```
FORMAT: code-server-<service-name>
```

### All Services
```
✓ code-server-postgres         - PostgreSQL Database (5432)
✓ code-server-redis            - Redis Cache (6379)
✓ code-server-redpanda         - Message Broker (9092)
✓ code-server-redpanda-console - Broker UI (8085)
✓ code-server-prometheus       - Metrics (9090)
✓ code-server-grafana          - Dashboards (3000)
✓ code-server-loki             - Logs (3100)
✓ code-server-alertmanager     - Alerts (9093)
✓ code-server-opa              - Policy Engine (8181)
✓ code-server-ollama           - LLM (11434)
✓ code-server-qdrant           - Vectors (6333-6334)
✓ code-server-oauth2-proxy     - Auth (4180)
✓ code-server-caddy            - API Gateway (80/443)
```

---

## Cluster Virtual IP (VIP)

```
CLUSTER_VIP = 192.168.168.250
```

### Network Layout
```
kushnir.cloud (DNS)
      ↓
192.168.168.250 (VIP - Load Balancer)
      ↙              ↘
192.168.168.31      192.168.168.42
(Replica 1)         (Replica 2)

All 13 services     All 13 services
(identical)         (identical)
```

### Access Points

| Endpoint | URL | Purpose |
|----------|-----|---------|
| **VIP (Primary)** | `http://192.168.168.250:3000` | Load balanced across both replicas |
| **Replica 1** | `http://192.168.168.31:3000` | Direct access (debug/diagnostics) |
| **Replica 2** | `http://192.168.168.42:3000` | Direct access (debug/diagnostics) |
| **Production Domain** | `https://kushnir.cloud` | After DNS configuration |

---

## Service Ports (via VIP or Direct)

```
:80    → Caddy HTTP (redirects to HTTPS in production)
:443   → Caddy HTTPS (TLS/SSL)
:3000  → Grafana (Dashboards)
:3100  → Loki (Logs)
:4180  → OAuth2-Proxy (Authentication)
:5432  → PostgreSQL (Internal only)
:6333  → Qdrant HTTP (Vector DB)
:6334  → Qdrant gRPC (Vector DB)
:6379  → Redis (Internal only)
:8085  → Redpanda Console (Broker UI)
:8181  → OPA (Policy Engine)
:9090  → Prometheus (Metrics)
:9092  → Redpanda (Message Broker)
:9093  → Alertmanager (Alerts)
:11434 → Ollama (LLM API)
```

---

## Common Commands

### Verify Containers Running (Replica 1)
```bash
ssh akushnir@192.168.168.31 'docker ps | grep code-server'
```

### View All Containers with New Names
```bash
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}" | sort'
```

### Check Specific Service Logs
```bash
ssh akushnir@192.168.168.31 'docker logs code-server-postgres -f'
ssh akushnir@192.168.168.31 'docker logs code-server-grafana -f'
ssh akushnir@192.168.168.31 'docker logs code-server-redis -f'
```

### Restart a Service
```bash
ssh akushnir@192.168.168.31 'docker-compose -f ~/code-server-enterprise/docker-compose.yml restart code-server-postgres'
```

### Access Grafana
```
Via VIP:      http://192.168.168.250:3000
Replica 1:    http://192.168.168.31:3000
Replica 2:    http://192.168.168.42:3000
```

### Check Replication Status
```bash
# PostgreSQL replication
ssh akushnir@192.168.168.31 'docker exec code-server-postgres \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"'

# Redis replication
ssh akushnir@192.168.168.31 'docker exec code-server-redis \
  redis-cli info replication'
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose-cluster.yml` | Container definitions with standard naming |
| `.env.cluster` | Environment variables (includes `CLUSTER_VIP=192.168.168.250`) |
| `CLUSTER_NAMING_CONVENTION.md` | Detailed naming documentation |
| `CLUSTER_DEPLOYMENT_GUIDE.md` | Deployment and operational procedures |

---

## Key Changes

### Before
- Container names: `postgres-db`, `redis-cache`, `caddy-gateway`, etc. ❌
- No standard naming convention ❌
- No VIP for load balancing ❌

### Now
- Container names: `code-server-postgres`, `code-server-redis`, `code-server-caddy`, etc. ✅
- Consistent naming across all services ✅
- VIP `192.168.168.250` for cluster load balancing ✅
- Single endpoint for production access ✅

---

## Deployment Steps

```bash
# 1. Update files
scp docker-compose-cluster.yml akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.31:~/code-server-enterprise/.env
scp docker-compose-cluster.yml akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.42:~/code-server-enterprise/.env

# 2. Deploy
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose up -d'
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose up -d'

# 3. Verify
ssh akushnir@192.168.168.31 'docker ps | grep code-server | wc -l'  # Should be 13
ssh akushnir@192.168.168.42 'docker ps | grep code-server | wc -l'  # Should be 13
```

---

## Cluster Architecture

```
ACTIVE/ACTIVE CLUSTER
┌────────────────────────────────────────────────────────────┐
│                   Cluster Domain                           │
│                   kushnir.cloud                            │
└────────────────────────────────────────────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        │                                 │
   ┌────▼─────┐                   ┌──────▼────┐
   │   VIP    │                   │ DNS/Load  │
   │ 192.168. │                   │ Balancer  │
   │ 168.250  │                   │  (HAProxy)│
   └────┬─────┘                   └──────┬────┘
        │                                 │
   ┌────┴──────────┬───────────────┬─────┘
   │               │               │
   ▼               ▼               ▼
R1 (31)      R2 (42)        (Optional backup)
13 svc       13 svc
Identical    Identical
```

---

## Support

For more information:
- Naming convention details: `CLUSTER_NAMING_CONVENTION.md`
- Deployment procedures: `CLUSTER_DEPLOYMENT_GUIDE.md`
- Cluster architecture: `ACTIVE_ACTIVE_CLUSTER_STATUS.md`

---

## Summary

✅ **Standard Naming**: All **35 containers** use `code-server-<service>` pattern  
✅ **VIP**: 192.168.168.250 configured for load balancing  
✅ **Active/Active**: Both replicas identical and symmetric with 35 services each  
✅ **Single Entry Point**: VIP provides one URL for all clients  
✅ **Production Ready**: Ready for domain configuration and HTTPS

