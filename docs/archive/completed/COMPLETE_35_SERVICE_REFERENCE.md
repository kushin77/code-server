# 35-Service Cluster Architecture - Complete Reference

**Status**: ✅ Complete  
**Date**: April 28, 2026  
**Services per Replica**: 35  
**Total Containers**: 70 (2 replicas × 35 services)

---

## All 35 Services with Standard Naming

### Infrastructure & Observability (7 Services)
```
 1. code-server-prometheus         - Metrics collection (9090)
 2. code-server-grafana            - Dashboards & visualization (3000)
 3. code-server-loki               - Log aggregation (3100)
 4. code-server-alertmanager       - Alert management (9093)
 5. code-server-tempo              - Distributed tracing
 6. code-server-otel-collector     - OpenTelemetry collector
 7. code-server-promtail           - Log forwarder
```

### Message Broker & Data Storage (5 Services)
```
 8. code-server-postgres           - PostgreSQL database (5432)
 9. code-server-redis              - Redis cache (6379)
10. code-server-redpanda           - Kafka-compatible broker (9092)
11. code-server-redpanda-console   - Broker UI (8085)
12. code-server-qdrant             - Vector database (6333-6334)
```

### AI & ML Services (6 Services)
```
13. code-server-ollama             - Local LLM inference (11434)
14. code-server-multimodal-ai      - Multimodal AI engine
15. code-server-memory-engine      - Vector memory & embeddings
16. code-server-reputation-engine  - Reputation scoring
17. code-server-paperclip          - Document processing & control plane
18. code-server-otel-collector     - Telemetry collection
```

### Agent Framework (6 Services)
```
19. code-server-agent-runtime      - Core agent execution engine
20. code-server-agent-code-reviewer - Code review agent
21. code-server-agent-doc-writer   - Documentation generator agent
22. code-server-agent-incident-responder - Incident response agent
23. code-server-agent-test-generator - Test generation agent
24. code-server-execution-scheduler - Task scheduling & execution
```

### Platform Services (7 Services)
```
25. code-server-activity-feed      - User activity tracking
26. code-server-env-provisioner    - Environment provisioning
27. code-server-control-plane-edge-api - Control plane API
28. code-server-edge-agent         - Primary edge agent
29. code-server-edge-agent-us-west-1 - US West regional agent
30. code-server-edge-agent-us-east-1 - US East regional agent
31. code-server-edge-agent-eu-central-1 - EU Central regional agent
```

### Gateway & Authentication (2 Services)
```
32. code-server-caddy              - API gateway/reverse proxy (80/443)
33. code-server-oauth2-proxy       - OAuth2 authentication (4180)
```

### Specialized Services (4 Services)
```
34. code-server-opa                - Policy enforcement engine (8181)
35. code-server-dcgm-exporter      - NVIDIA GPU metrics exporter
36. code-server-edge-agent-health-monitor - Health monitoring
```

---

## Service Categories by Function

### Observability Stack (7 services)
- **Metrics**: Prometheus, Grafana
- **Logs**: Loki, Promtail
- **Traces**: Tempo, OTel Collector
- **Alerts**: Alertmanager

### Data Layer (5 services)
- **Relational**: PostgreSQL (replication)
- **Cache**: Redis (persistence)
- **Message Broker**: Redpanda (cluster), Redpanda-Console
- **Vector DB**: Qdrant (similarity search)

### AI/ML Engines (6 services)
- **LLM**: Ollama (local inference)
- **AI Processing**: Multimodal AI, Memory Engine, Reputation Engine
- **Document Processing**: Paperclip
- **Telemetry**: OTel Collector

### Agent Framework (6 services)
- **Core Runtime**: Agent-Runtime, Execution-Scheduler
- **Specialized Agents**: Code-Reviewer, Doc-Writer, Incident-Responder, Test-Generator

### Platform (7 services)
- **Activity**: Activity-Feed, Env-Provisioner
- **Control Plane**: Control-Plane-Edge-API
- **Regional Agents**: Edge-Agent (primary + 3 regions)
- **Health**: Edge-Agent-Health-Monitor

### Ingress & Auth (2 services)
- **Gateway**: Caddy (80/443)
- **Authentication**: OAuth2-Proxy (4180)

### Infrastructure (4 services)
- **Policy**: OPA (8181)
- **Monitoring**: DCGM-Exporter (GPU metrics)

---

## Cluster Architecture

```
                    kushnir.cloud (DNS)
                           │
                ┌──────────┴──────────┐
                │                     │
            VIP 192.168.168.250    (Direct access)
         [HAProxy/nginx LB]            │
                │                      │
        ┌───────┴───────┐              │
        │               │              │
        ▼               ▼              ▼
   Replica 1       Replica 2      (Debug)
   192.168.      192.168.
   168.31        168.42

35 Services     35 Services      Access via:
Identical       Identical        - 192.168.168.31:PORT
Symmetric       Symmetric        - 192.168.168.42:PORT
```

---

## Deployment Configuration

### Files
```
docker-compose-cluster.yml  - All 35 services with code-server-* naming
.env.cluster               - VIP: 192.168.168.250, credentials, replication config
```

### Required Environment Variables
```
CLUSTER_VIP=192.168.168.250
CLUSTER_HOST_1=192.168.168.31
CLUSTER_HOST_2=192.168.168.42
NAS_HOST=192.168.168.56
APEX_DOMAIN=kushnir.cloud
```

### Key Service Configurations

**PostgreSQL Replication**
```
- Bidirectional WAL streaming
- max_wal_senders=10
- wal_level=replica
- Replication user: replicator
```

**Redis Persistence**
```
- RDB snapshots enabled
- Replication via TCP
- Persistence replicated between replicas
```

**Redpanda Multi-Node**
```
- Broker nodes: code-server-redpanda on both replicas
- Topic replication factor: 2
- ISR quorum: 2
```

---

## Access Points

### Via VIP (Recommended - Production)
```
http://192.168.168.250:3000     → Grafana
http://192.168.168.250:9090     → Prometheus
http://192.168.168.250:3100     → Loki
http://192.168.168.250:9093     → Alertmanager
http://192.168.168.250:8085     → Redpanda Console
http://192.168.168.250:8181     → OPA
http://192.168.168.250:11434    → Ollama
http://192.168.168.250/         → Caddy Gateway
https://kushnir.cloud/          → Production domain (after DNS config)
```

### Direct Replica Access (Debug)
```
Replica 1:
http://192.168.168.31:3000      → Grafana
http://192.168.168.31:9090      → Prometheus
...

Replica 2:
http://192.168.168.42:3000      → Grafana
http://192.168.168.42:9090      → Prometheus
...
```

---

## Verification Commands

### Count Running Services
```bash
# Should show 35 services on each replica
ssh akushnir@192.168.168.31 'docker ps | grep code-server | wc -l'
ssh akushnir@192.168.168.42 'docker ps | grep code-server | wc -l'
```

### List All Running Containers
```bash
# Replica 1
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep code-server | sort'

# Replica 2
ssh akushnir@192.168.168.42 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep code-server | sort'
```

### Check Specific Service
```bash
# PostgreSQL on Replica 1
ssh akushnir@192.168.168.31 'docker logs code-server-postgres -f'

# Agent Runtime on Replica 1
ssh akushnir@192.168.168.31 'docker logs code-server-agent-runtime -f'

# Ollama on Replica 2
ssh akushnir@192.168.168.42 'docker logs code-server-ollama -f'
```

### Verify Replication
```bash
# PostgreSQL replication status
ssh akushnir@192.168.168.31 'docker exec code-server-postgres \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"'

# Redpanda cluster status
ssh akushnir@192.168.168.31 'docker exec code-server-redpanda rpk cluster info'

# Redis replication
ssh akushnir@192.168.168.31 'docker exec code-server-redis redis-cli info replication'
```

---

## Deployment Steps

```bash
# 1. Copy files to both replicas
for host in 192.168.168.31 192.168.168.42; do
  scp docker-compose-cluster.yml akushnir@$host:~/code-server-enterprise/docker-compose.yml
  scp .env.cluster akushnir@$host:~/code-server-enterprise/.env
done

# 2. Deploy on Replica 1
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose up -d'

# 3. Wait for stabilization
sleep 60

# 4. Deploy on Replica 2
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose up -d'

# 5. Verify
echo "=== Replica 1 Services ===" && \
ssh akushnir@192.168.168.31 'docker ps -q | wc -l' && \
echo "=== Replica 2 Services ===" && \
ssh akushnir@192.168.168.42 'docker ps -q | wc -l'
```

---

## Service Dependencies

### Critical Path (must start first)
1. **Data Layer**: postgres, redis, redpanda
2. **Observability**: prometheus, loki, tempo
3. **Platform Services**: all others depend on these

### Agent Services Dependencies
- All agents depend on: redis, postgres, redpanda
- Agent-Runtime must start before other agents

### AI Services Dependencies
- Ollama, Memory-Engine, Multimodal-AI dependencies:
  - redis (cache)
  - postgres (persistence)
  - qdrant (vectors)

---

## Scaling Notes

- **35 services per replica** = Balanced workload distribution
- **2 replicas × 35 services** = 70 total containers for HA/LB
- **VIP**: Abstracts replica details from clients
- **Active/Active**: No primary/replica distinction—both equal

---

## Next Steps

1. ✅ Updated docker-compose-cluster.yml with all 35 services
2. ✅ Standard naming applied: code-server-<service>
3. ✅ VIP configuration: 192.168.168.250
4. ⏳ Deploy to both replicas
5. ⏳ Configure HAProxy/nginx at VIP
6. ⏳ Point kushnir.cloud DNS to VIP
7. ⏳ Configure HTTPS/TLS

---

## Summary

- **Services**: 35 per replica (70 total)
- **Naming**: All follow `code-server-<service>` pattern
- **Architecture**: Active/Active with VIP load balancing
- **Status**: Ready for deployment

