# Infrastructure Configuration Reference — Complete Guide

**Purpose**: Single source of truth for all infrastructure configuration, network topology, and operational procedures  
**Audience**: Operations Engineers, SRE, DevOps, Infrastructure Team  
**Updated**: April 24, 2026  
**Status**: ✅ Production-Ready  

---

## Table of Contents

1. [Cluster Architecture](#cluster-architecture)
2. [Network Topology](#network-topology)  
3. [Service Inventory](#service-inventory)
4. [Configuration Management](#configuration-management)
5. [DNS & Load Balancing](#dns--load-balancing)
6. [Database & Storage](#database--storage)
7. [Security & Authentication](#security--authentication)
8. [Monitoring & Logging](#monitoring--logging)
9. [Environment Variables](#environment-variables)
10. [Docker Image Versions](#docker-image-versions)

---

## Cluster Architecture

### Multi-Replica Active-Active Design

```
┌─────────────────────────────────────────────────────────────┐
│                        LOAD BALANCER                        │
│                    (HAProxy / Caddy)                        │
│         Health check based round-robin (< 5s failover)      │
└─────────────────────────────────────────────────────────────┘
              ↓                              ↓
    ┌─────────────────┐            ┌─────────────────┐
    │  Replica 1 (R1) │            │  Replica 2 (R2) │
    │  192.168.168.31 │            │  192.168.168.42 │
    │  Ubuntu 22.04   │            │  Ubuntu 22.04   │
    │  akushnir user  │            │  akushnir user  │
    └─────────────────┘            └─────────────────┘
        ↓         ↓                    ↓         ↓
    [Code-]  [DB]  [Cache]        [Code-]  [DB]  [Cache]
     Server  Prim  Sentinel        Server  Repl  Sentinel
                  ↑────────────────────↑
                   Replication (< 1s lag)
                   
    ↓────────────────────────────────────↓
         NAS Storage (192.168.168.56)
         Persistent volumes for all replicas
```

### Replica Specifications

| Component | Value |
|-----------|-------|
| **Primary IP** | 192.168.168.31 |
| **Secondary IP** | 192.168.168.42 |
| **OS** | Ubuntu 22.04 LTS |
| **SSH User** | akushnir |
| **SSH Port** | 22 (standard) |
| **SSH Keys** | ~/.ssh/kushnir-prod (Ed25519) |
| **Docker Version** | 27.0+ |
| **docker-compose Version** | 2.20+ |
| **Network** | net-app (overlay network) |
| **Deployment Model** | Parallel (not sequential) |

### Failover Characteristics

| Property | Value |
|----------|-------|
| **Detection Time** | < 5 seconds |
| **Failover Time** | < 1 second |
| **RTO** | 5 seconds |
| **RPO** | < 1 second |
| **Replication Lag** | < 1 second (typical) |
| **Heartbeat Interval** | 10 seconds |
| **Max Healthcheck Fails** | 3 (30 second threshold) |

---

## Network Topology

### Domains & Subdomains

```
kushnir.cloud               (Apex domain, Portal landing page)
  ├── ide.kushnir.cloud     (Code-Server IDE, proxied via Caddy)
  ├── api.kushnir.cloud     (Backend API, proxied via Caddy)
  ├── monitoring.kushnir.cloud  (Grafana dashboards)
  └── observability.kushnir.cloud (Prometheus, Loki, Jaeger)
```

### Network Interfaces & Ports

#### Replica Nodes (192.168.168.31 / .42)

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Caddy (Reverse Proxy) | 80/443 | HTTP/HTTPS | Ingress point for all traffic |
| Code-Server | 8443 | HTTPS | IDE backend service |
| PostgreSQL | 5432 | TCP | Database access (internal) |
| Redis | 6379 | TCP | Cache/session store (internal) |
| Redis Sentinel | 26379 | TCP | Redis failover (internal) |
| Prometheus | 9090 | HTTP | Metrics collection (internal) |
| Grafana | 3000 | HTTP | Dashboards (proxied via Caddy) |
| AlertManager | 9093 | HTTP | Alert routing (internal) |
| Jaeger | 6831 | UDP | Distributed tracing (internal) |
| Loki | 3100 | HTTP | Log aggregation (internal) |
| node-exporter | 9100 | HTTP | Host metrics (internal) |
| cAdvisor | 8080 | HTTP | Container metrics (internal) |
| HAProxy Stats | 8080 | HTTP | Load balancer status page |

#### Loadbalancer

| Service | Port | Purpose |
|---------|------|---------|
| HAProxy | 80/443 | Public ingress (proxies to both replicas) |
| HAProxy Stats | 8080 | Admin statistics page |

### Internal Network (net-app)

**Purpose**: Isolated application network for inter-service communication  
**CIDR**: 10.0.9.0/24 (configurable in docker-compose.yml)  
**DNS**: Automatic service discovery by container name  

**Connected Services**:
- caddy (reverse proxy)
- code-server (IDE backend)
- postgres-primary (database master)
- postgres-replica (database replica)
- redis-primary (cache master)
- redis-replica (cache replica)
- redis-sentinel (failover coordinator)
- prometheus (metrics collector)
- grafana (dashboards)
- alertmanager (alert router)
- jaeger (trace collector)
- loki (log aggregator)
- oauth2-proxy-portal (session gateway)

**Communication Example**:
```bash
# Inside container, reach Postgres via hostname
psql -h postgres-primary -U postgres -d mydb

# Via docker-compose on host
docker-compose exec caddy curl -s http://prometheus:9090/api/v1/status/config
```

---

## Service Inventory

### Core Services (Always Running)

#### 1. Caddy (Reverse Proxy)
```yaml
Service: caddy
Image: caddy:2.8-alpine-full
Port: 80/443
Role: Ingress controller, HTTPS termination, service routing
Config: Caddyfile (mounted from host)
Health Check: curl -s http://localhost:2019/config | jq '.routes | length'
Restart: Always
```

**Routing Rules**:
- `kushnir.cloud/*` → oauth2-proxy-portal:4180
- `ide.kushnir.cloud/*` → oauth2-proxy (or code-server:8443 if no auth)
- `monitoring.kushnir.cloud/*` → grafana:3000
- `observability.kushnir.cloud/*` → prometheus:9090

#### 2. Code-Server (IDE Backend)
```yaml
Service: code-server
Image: codercom/code-server:4.115.0
Port: 8443 (internal), exposed via Caddy 443 (external)
Role: VS Code IDE backend, workspace persistence
Config: ~/.config/code-server/config.yaml (mounted from host)
Health Check: curl -s https://localhost:8443/api/v1/applications/overview
Restart: Always
Data Volumes:
  - /root/.config/code-server (settings, extensions)
  - /root/.local/share/code-server (workspace state)
```

**Environment**:
- `PASSWORD`: Set from GSM secret
- `SUDO_PASSWORD`: Set from GSM secret
- `BIND_ADDR`: 0.0.0.0:8443

#### 3. PostgreSQL Primary (Database Master)
```yaml
Service: postgres-primary
Image: postgres:15-alpine
Port: 5432 (internal)
Role: Primary database for all application data
Config: postgres-primary.conf (streaming replication)
Health Check: pg_isready -U postgres -h localhost
Restart: Always
Data Volume: /var/lib/postgresql/data
Replication: Streaming to replica (< 1s lag)
```

**Replication Configuration**:
- Streaming replication mode
- Replica connection: `replication_mode=streaming`
- Max replication slots: 10
- Wal_keep_size: 1 GB (prevent replication slot invalidation)

#### 4. PostgreSQL Replica (Database Slave)
```yaml
Service: postgres-replica
Image: postgres:15-alpine
Port: 5432 (internal, read-only)
Role: Read replica for scaling reads, failover candidate
Config: postgres-replica.conf (hot standby)
Replication: Follows primary (< 1s lag)
Failover: Can be promoted to primary via `pg_ctl promote`
```

#### 5. Redis Primary (Session Cache Master)
```yaml
Service: redis-primary
Image: redis:7-alpine
Port: 6379 (internal)
Role: Session cache, distributed locks, real-time data
Replication: Async replication to redis-replica
Health Check: redis-cli ping
Restart: Always
Max Memory: 2GB (LRU eviction)
```

#### 6. Redis Replica (Cache Replica)
```yaml
Service: redis-replica
Image: redis:7-alpine
Port: 6379 (internal)
Role: Read-only replica, backup for primary failure
Replication: Follows primary
Sentinel Monitored: Yes
```

#### 7. Redis Sentinel (Failover Coordinator)
```yaml
Service: redis-sentinel
Image: redis:7-alpine (runs sentinel mode)
Port: 26379 (internal)
Role: Monitors Redis primary/replica, triggers failover
Config: /etc/redis/sentinel.conf
Failover Trigger: 2 out of 3 sentinels down → promote replica
Quorum: 2 (2 sentinels agree to promote)
```

### Monitoring & Observability Stack

#### 8. Prometheus (Metrics Collection)
```yaml
Service: prometheus
Image: prom/prometheus:v2.49.1
Port: 9090 (internal)
Role: Metrics scraping, alerting rules, time-series database
Config: /etc/prometheus/prometheus.yml (scrape targets)
Alert Rules: /etc/prometheus/rules/sla-rules.yml
Retention: 15 days (default)
Data Volume: /prometheus
```

**Scrape Targets**:
- node-exporter (host metrics)
- cAdvisor (container metrics)
- code-server (application metrics)
- postgres (database metrics)
- redis (cache metrics)

#### 9. Grafana (Dashboards & Alerting)
```yaml
Service: grafana
Image: grafana/grafana:10.4.1
Port: 3000 (internal, proxied via Caddy)
Role: Metric visualization, alert management, status dashboards
Config: /etc/grafana/provisioning (datasources, dashboards)
Default Datasource: Prometheus
Dashboards: 11-panel cluster health dashboard
Alerting: Integrated with AlertManager
```

**Default Login** (on fresh deployment):
- Username: admin
- Password: admin (change immediately)

#### 10. AlertManager (Alert Routing)
```yaml
Service: alertmanager
Image: prom/alertmanager:v0.26.0
Port: 9093 (internal)
Role: Alert aggregation, routing, silencing
Config: /etc/alertmanager/alertmanager.yml
Alert Routes:
  - Critical (P0): PagerDuty, SMS, Slack
  - Warning (P1): Slack, Email
  - Info (P2): Slack monitoring channel
```

#### 11. Loki (Log Aggregation)
```yaml
Service: loki
Image: grafana/loki:2.9.3
Port: 3100 (internal)
Role: Log storage and querying
Config: /etc/loki/local-config.yaml
Log Retention: 3 days (default)
```

#### 12. Jaeger (Distributed Tracing)
```yaml
Service: jaeger
Image: jaegertracing/all-in-one:1.51
Port: 6831 (UDP), 16686 (HTTP UI)
Role: Distributed request tracing, performance debugging
Retention: 72 hours
```

### Optional/On-Demand Services

#### Appsmith (Portal Application)
```yaml
Service: appsmith (optional)
Image: appsmith/appsmith:v1.47.0
Port: 80 (internal)
Role: Low-code portal dashboard
Database: postgres-primary (dedicated schema)
Authentication: OAuth2 (Google)
Profile: appsmith (conditionally started with COMPOSE_PROFILES)
```

#### Ollama (AI Model Server)
```yaml
Service: ollama (optional, GPU support)
Image: ollama/ollama:0.1.45
Port: 11434
Role: Local LLM inference, embeddings
GPU Support: NVIDIA CUDA 12.2
Profiles: ai (start with COMPOSE_PROFILES=ai)
Models: Preloaded (configurable)
```

---

## Configuration Management

### Configuration Hierarchy (Priority Order)

```
1. Environment Variables (Highest Priority)
   ├── GSM Secrets (via bootstrap script)
   └── .env file (local development fallback)

2. Docker Compose Overrides
   ├── docker-compose.override.yml (local)
   └── -f override.yml (CLI flag)

3. Service Config Files
   ├── Caddyfile
   ├── prometheus.yml
   ├── alertmanager.yml
   └── config files (mounted volumes)

4. Docker Image Defaults (Lowest Priority)
   └── Hardcoded in Dockerfile
```

### Environment Variables

**Source**: GSM secrets bootstrap → loaded into docker-compose

```bash
# GSM Bootstrap (runs first)
source scripts/fetch-gsm-secrets.sh

# Populates:
export DEPLOY_HOST=192.168.168.31
export REGISTRY_URL=registry.kushnir.cloud
export POSTGRES_PASSWORD=<secret>
export REDIS_PASSWORD=<secret>
export CODE_SERVER_PASSWORD=<secret>
```

**Common Vars**:
- `DEPLOY_HOST`: Primary replica IP
- `APEX_DOMAIN`: kushnir.cloud
- `IDE_DOMAIN`: ide.kushnir.cloud
- `POSTGRES_PASSWORD`: DB master password
- `REDIS_PASSWORD`: Cache password
- `CODE_SERVER_PASSWORD`: IDE access password

### Docker Compose Profiles

**Purpose**: Conditionally enable services

```bash
# All core services
docker-compose up -d

# With Appsmith portal
COMPOSE_PROFILES=appsmith docker-compose up -d appsmith

# With AI/Ollama
COMPOSE_PROFILES=ai docker-compose up -d ollama

# With both
COMPOSE_PROFILES=appsmith,ai docker-compose up -d
```

---

## DNS & Load Balancing

### DNS Resolution

**Zone**: kushnir.cloud (managed via DNS provider)

```
kushnir.cloud          → LB VIP (HAProxy/Caddy health-check endpoint)
ide.kushnir.cloud      → LB VIP (routes to code-server via Caddy)
api.kushnir.cloud      → LB VIP (routes to backend API)
monitoring.kushnir.cloud    → LB VIP (routes to Grafana)
observability.kushnir.cloud → LB VIP (routes to Prometheus)
```

**Resolution Method**: 
- External DNS points all subdomains to single LB VIP
- HAProxy/Caddy health-checks determine which replica is active
- < 5 second failover when replica goes down

### Load Balancer (HAProxy)

**Config**: `/etc/haproxy/haproxy.cfg` (on LB host)

```
frontend public_https
  bind *:443 ssl crt /etc/ssl/certs/kushnir.cloud.pem
  mode http
  default_backend replicas_https

backend replicas_https
  mode http
  balance roundrobin
  
  server r31 192.168.168.31:443 check inter 10s rise 2 fall 3
  server r42 192.168.168.42:443 check inter 10s rise 2 fall 3
  
  # Health check endpoint
  http-check expect string "200 OK"
  http-check send "GET /health HTTP/1.0\r\nHost: kushnir.cloud\r\n\r\n"
```

**Health Check Behavior**:
- Interval: 10 seconds
- Success threshold: 2 consecutive checks
- Failure threshold: 3 consecutive checks (30 second detection)
- Failover action: Stop sending traffic to failed replica
- Auto-recovery: Resume traffic when replica recovers

### Caddy Configuration (Per Replica)

**Location**: `Caddyfile` (mounted in caddy container)

```caddy
# Portal landing page (OAuth protected)
kushnir.cloud {
    reverse_proxy oauth2-proxy-portal:4180
    encode gzip
    header ?Cache-Control "public, max-age=3600"
}

# IDE (OAuth protected)
ide.kushnir.cloud {
    reverse_proxy code-server:8443 {
        header_uri -l
    }
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    encode gzip
}

# Monitoring (OAuth protected)
monitoring.kushnir.cloud {
    reverse_proxy grafana:3000
    header Authorization "Bearer {token}"
}

# Observability (OAuth protected)
observability.kushnir.cloud {
    reverse_proxy prometheus:9090
    header X-Forwarded-For "{http.request.remote.host}"
}
```

---

## Database & Storage

### PostgreSQL Deployment

#### Streaming Replication

```
Replica 1 (Primary)        Replica 2 (Standby)
192.168.168.31:5432   →←  192.168.168.42:5432
   postgres-primary         postgres-replica
   
WAL logs sent every 16MB or 30 seconds
Replication lag: < 1 second (typical)
```

**Failover Procedure** (Manual):

```bash
# On standby (R42), promote to primary
docker-compose exec postgres-replica pg_ctl promote

# Verify new primary is accepting writes
docker-compose exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return: f (false = not in recovery = primary)
```

### NAS Storage

**Mount**: 192.168.168.56 (via CIFS/SMB)  
**Path on Replicas**: `/mnt/nas`  
**Credentials**: Stored in .env file (GSM backed)

**Directory Structure**:

```
/mnt/nas/
├── persistent/
│   ├── postgres/          # Database backup
│   ├── redis/             # Cache persistence (RDB)
│   └── code-server/       # IDE workspace backups
└── hot/
    └── docker-images/     # Docker image cache layers
```

**Backup Strategy**:
- Database: `pg_dump` → `/mnt/nas/persistent/postgres/`
- Redis: RDB snapshots → `/mnt/nas/persistent/redis/`
- Code-Server: Workspace tar → `/mnt/nas/persistent/code-server/`

### Data Persistence

| Service | Data Location | Persistence |
|---------|---------------|-------------|
| PostgreSQL | /var/lib/postgresql/data | RDB files (persistent) |
| Redis | /data | RDB snapshots (every 6h) |
| Code-Server | /root/.local/share | Workspace files (persistent) |
| Prometheus | /prometheus | TSDB blocks (15-day retention) |
| Loki | /loki | Log index (3-day retention) |
| Grafana | /var/lib/grafana | Dashboards, datasources (persistent) |

---

## Security & Authentication

### OAuth2 Flow

```
User                    kushnir.cloud              Google OAuth
│                           │                           │
├─ Visit portal ─────────→ Caddy ───────────────────→ oauth2-proxy
│                           │                           │
│                        (No Session)            (Redirect to Google)
│                           │←─────────────────────────│
│←─────────────────────────────────────────────────────│
│                     (Google Login Page)
│
│─ Enter credentials ──→ Google ─────────────────────→ oauth2-proxy
│                           │                           │
│                   (Validates credentials)    (Creates session)
│                           │←─────────────────────────│
│←─────────────────────────────────────────────────────│
│
│─ Access granted ────→ kushnir.cloud ───────────→ Appsmith
│                    (Session cookie set)
│
│─ Navigate to IDE ──→ ide.kushnir.cloud ─ (checks session cookie)
│                                         ─ (session valid → no re-auth)
```

### Session Management

**Storage**: Redis (distributed, shared across replicas)  
**Cookie**: `oauth2_proxy_<domain>` (SameSite=Lax, Secure, HttpOnly)  
**Domain**: `.kushnir.cloud` (wildcard for all subdomains)  
**TTL**: 24 hours (configurable)  
**Refresh**: Automatic (background) before expiry  

**Session Sharing**:
- All replicas connect to same Redis instance
- Session cookie domain: `.kushnir.cloud`
- Navigation across subdomains: No re-authentication required
- Logout: Clears Redis session + cookie (all subdomains affected)

### TLS Certificates

**Provider**: Let's Encrypt (via ACME protocol)  
**Renewal**: Automatic by Caddy (checks 30 days before expiry)  
**Certificate Pinning**: Not used (standard public cert)  

**Certificate Paths** (in Caddy container):
```
/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
├── kushnir.cloud/
│   ├── kushnir.cloud.crt
│   └── kushnir.cloud.key
└── ide.kushnir.cloud/
    └── ... (combined into single cert with SAN)
```

---

## Monitoring & Logging

### Metrics Collection

**Prometheus Scrape Targets**:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
  
  - job_name: 'containers'
    static_configs:
      - targets: ['cadvisor:8080']
  
  - job_name: 'database'
    static_configs:
      - targets: ['postgres-exporter:9187']
  
  - job_name: 'cache'
    static_configs:
      - targets: ['redis:6379']
```

### Alert Rules (SLA Compliance)

**Rules File**: `/etc/prometheus/rules/sla-rules.yml`

```yaml
groups:
  - name: deployment
    rules:
      - alert: HighDeploymentFailureRate
        expr: (increase(deployments_failed[1h]) / increase(deployments_total[1h])) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Deployment failure rate > 10%"
```

### Log Aggregation

**Loki** collects logs from all containers via docker log driver:

```bash
# Query logs for code-server service
curl -s 'http://localhost:3100/loki/api/v1/query?query={job="code-server"}' | jq

# View recent errors
curl -s 'http://localhost:3100/loki/api/v1/query?query={level="ERROR"}' | jq
```

---

## Environment Variables

### Required Variables (GSM Secrets)

```bash
# Database
POSTGRES_PASSWORD=<secret>
POSTGRES_REPLICATION_PASSWORD=<secret>

# Redis
REDIS_PASSWORD=<secret>

# Code-Server
CODE_SERVER_PASSWORD=<secret>

# OAuth2
OAUTH2_CLIENT_ID=<google_oauth_id>
OAUTH2_CLIENT_SECRET=<google_oauth_secret>

# Infrastructure
DEPLOY_HOST=192.168.168.31
APEX_DOMAIN=kushnir.cloud
IDE_DOMAIN=ide.kushnir.cloud
```

### Optional Variables

```bash
# Monitoring
PROMETHEUS_RETENTION_DAYS=15
LOKI_RETENTION_DAYS=3

# Performance
REDIS_MAX_MEMORY=2gb
POSTGRES_SHARED_BUFFERS=256MB
POSTGRES_EFFECTIVE_CACHE_SIZE=1GB

# Ollama (if enabled)
OLLAMA_MODEL_NAME=mistral
OLLAMA_PULL_MODEL=true
```

---

## Docker Image Versions

### Pinned Production Versions

```yaml
caddy:                    2.8-alpine-full
code-server:             4.115.0
postgres:                15-alpine
redis:                   7-alpine
prometheus:              v2.49.1
grafana:                 10.4.1
alertmanager:            v0.26.0
loki:                    2.9.3
jaeger:                  1.51
appsmith:                v1.47.0 (optional)
ollama:                  0.1.45 (optional)
node-exporter:           v1.7.0
cadvisor:                v0.48.1
oauth2-proxy:            v7.15.0
```

### Image Pull Policy

- **Production**: `imagePullPolicy: IfNotPresent` (use cached, pull if missing)
- **CI/CD**: `imagePullPolicy: Always` (always pull latest)

**Registry**: Default Docker Hub  
**Authentication**: Via .env secrets (registry credentials)

---

## Quick Reference

### Common Operations

```bash
# SSH to primary replica
ssh -i ~/.ssh/kushnir-prod akushnir@192.168.168.31

# Check cluster status
docker-compose ps

# View logs (all services)
docker-compose logs -f

# Restart service
docker-compose restart caddy

# Deploy to both replicas
for host in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$host 'cd code-server-enterprise && \
    docker-compose pull && \
    docker-compose up -d'
done
```

### Health Checks

```bash
# Database replication lag
psql -h 192.168.168.31 -U postgres -c "SELECT slot_name, restart_lsn FROM pg_replication_slots;"

# Redis failover status
redis-cli -p 26379 sentinel masters

# Load balancer status
curl http://192.168.168.31:8080/stats

# Portal health
curl -s https://kushnir.cloud/health
curl -s https://ide.kushnir.cloud/health
```

---

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Maintenance**: Review quarterly or after major infrastructure changes  
**Owner**: Infrastructure Team / SRE  
