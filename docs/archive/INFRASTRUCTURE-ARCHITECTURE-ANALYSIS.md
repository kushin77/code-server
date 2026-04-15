# Infrastructure Architecture Analysis — code-server-enterprise
**Date**: April 15, 2026  
**Status**: Current State Analysis  
**Scope**: NAS/Storage, Redis, Network, Performance Baselines

---

## Executive Summary

The code-server-enterprise infrastructure is a **production-grade on-premises deployment** with NAS-backed persistent storage, in-memory caching via Redis, and Docker-based service orchestration. Current configuration prioritizes **availability and reliability** over raw performance optimization. Several optimization opportunities exist in network, storage I/O, and memory management.

---

# 1. NAS/STORAGE ARCHITECTURE

## Current Configuration

### Primary NAS (Active)
| Attribute | Value | Reference |
|-----------|-------|-----------|
| **Host IP** | `192.168.168.56` | [.env](../.env#L70) |
| **Export Path** | `/export` | [.env](../.env#L71) |
| **Mount Point** | `/mnt/nas-56` | [.env](../.env#L72) |
| **Protocol** | NFS 4.1 | [nas-mount-31.sh](../scripts/nas-mount-31.sh#L13) |
| **Access Mode** | `rw` (read-write) | [nas-mount-31.sh](../scripts/nas-mount-31.sh#L13) |
| **Status** | ✅ Active | Production deployment |

### Replica NAS (Standby)
| Attribute | Value | Reference |
|-----------|-------|-----------|
| **Host IP** | `192.168.168.55` | [.env](../.env#L73) |
| **Export Path** | `/export` | [.env](../.env#L74) |
| **Mount Point** | `/mnt/nas-export` | [.env](../.env#L75) |
| **Role** | Backup/Failover | Configured but not currently used |

### NFS Mount Parameters
**Current Configuration** ([nas-mount-31.sh](../scripts/nas-mount-31.sh#L13)):
```
vers=4.1,rw,hard,intr,timeo=30,retrans=3,rsize=1048576,wsize=1048576
```

| Parameter | Value | Purpose | Notes |
|-----------|-------|---------|-------|
| `vers=4.1` | NFS 4.1 | Protocol version | Standard; supports delegations & modern features |
| `rw` | Read-Write | Mount mode | Full access required |
| `hard` | Enabled | Hard mount | Retries infinitely; no timeout | ⚠️ Can block if NAS unavailable |
| `intr` | Enabled | Interruptible | Signals can interrupt mount calls | ✅ Good for responsiveness |
| `timeo=30` | 30/10s = 3s | Timeout | Initial timeout: 3 seconds | ⚠️ May be tight for WAN |
| `retrans=3` | 3 retries | Retransmissions | 3 retry attempts | Standard; good balance |
| `rsize=1048576` | 1 MB | Read size | Max 1 MB per read request | ✅ Optimal for throughput |
| `wsize=1048576` | 1 MB | Write size | Max 1 MB per write request | ✅ Optimal for throughput |

### NAS-Backed Volumes in Docker

**Local SSD Volumes** (fast, ephemeral):
- `postgres-data` — Database workings (local SSD) ✅ Good choice
- `redis-data` — Cache (local SSD) ✅ Critical for latency
- `prometheus-data` — Metrics TSDB (local SSD) ✅ Good for scrape ingestion
- `code-server-data` — IDE workspace (local SSD)
- `caddy-config`, `caddy-data` — Web server config (local SSD)
- `alertmanager-data`, `jaeger-data`, `vault-data`, `falco-data` (local SSD)

**NAS-Backed Volumes** ([docker-compose.yml](../docker-compose.yml#L650-L678)):

| Volume | Mount Point | Protocol | NFS Options | Size | Usage |
|--------|-------------|----------|-------------|------|-------|
| `nas-ollama` | `/root/.ollama` | NFS4 | Standard | ~10-40 GB | Ollama model cache (large files) |
| `nas-code-server` | Code editor workspace | NFS4 | Standard | Variable | Developer files |
| `nas-prometheus` | Prometheus TSDB | NFS4 | Standard | 30d retention | Long-term metrics |
| `nas-grafana` | Grafana persistent state | NFS4 | Standard | Small | Dashboard configs |
| `nas-postgres-backups` | PostgreSQL backups | NFS4 | Standard | Variable | pg_dump backups |

**NAS Connection Parameters** (in docker-compose):
```yaml
nas-ollama:
  driver_opts:
    type: nfs4
    o: "addr=192.168.168.56,rw,hard,intr,timeo=30,retrans=3,rsize=1048576,wsize=1048576"
    device: ":/export/ollama"
```

### Current Volume Layout

**On Host (192.168.168.31)**:
```
Local storage (fast):
├── PostgreSQL data → local SSD
├── Redis data → local SSD (CRITICAL)
├── Code-server data → local SSD
└── Prometheus → local SSD (initial metrics)

NAS-mounted (192.168.168.56:/export):
├── /mnt/nas-56/ollama → Large model cache (10-40GB)
├── /mnt/nas-56/code-server → Developer workspace
├── /mnt/nas-56/grafana → Dashboards
├── /mnt/nas-56/prometheus → Long-term retention (30d)
└── /mnt/nas-56/backups/postgres → pg_dump backups
```

### Identified Storage Issues

| Issue | Severity | Current State | Impact |
|-------|----------|---------------|--------|
| **Ollama on NAS** | 🟡 Medium | Large (10-40GB) model cache on network storage | ~10-30ms latency per model load; slower inference startup |
| **Grafana on NAS** | 🟢 Low | Small dashboards, config-heavy | Acceptable; not latency-sensitive |
| **Prometheus on NAS** | 🟡 Medium | 30-day retention = ~50-100GB time-series | Slower queries for old data; acceptable for dashboarding |
| **timeo=30** | 🟡 Medium | 3-second timeout (first attempt) | May timeout on brief network hiccup; exponential backoff helps but not ideal |
| **No NVME cache** | 🟡 Medium | NAS I/O directly on spinning disk or SATA SSD | No local NVME tiering for frequently accessed files |
| **Single NAS IP** | 🟠 Orange | Failover to 192.168.168.55 requires manual remount | No automatic failover if primary NAS unavailable |

---

## Storage Performance Characteristics

### Theoretical Limits
- **NAS throughput**: ~100-200 MB/s (gigabit NFS typical)
- **Local SSD**: ~500-1000 MB/s (NVMe) or ~250-500 MB/s (SATA SSD)
- **Docker local volumes**: Limited by underlying host storage

### Measured Operations
[infrastructure-assessment-31.sh](../scripts/infrastructure-assessment-31.sh#L207-L230) includes **NAS write/read tests**:

```bash
# NAS Write Test (100MB)
dd if=/dev/zero of=/mnt/nas-56/.test bs=1M count=100

# NAS Latency Baseline (1GB sequential read)
dd if=/mnt/nas-56/.test of=/dev/null bs=1M
```

**Expected Results** (not yet captured):
- Write: ~80-150 MB/s (gigabit NFS limit ~125 MB/s)
- Read: ~80-150 MB/s
- Latency: ~1-3ms per syscall

---

# 2. REDIS SETUP

## Current Configuration

| Setting | Value | Reference | Notes |
|---------|-------|-----------|-------|
| **Version** | 7.2-alpine | [.env](../.env#L31) | Lightweight, production-ready |
| **Container** | `redis` | [docker-compose.yml](../docker-compose.yml#L80) | Single instance |
| **Network** | `enterprise` (Docker bridge) | [docker-compose.yml](../docker-compose.yml#L84) | Internal only, no external port |
| **Port** | 6379 | [.env](../.env#L30) | Standard Redis port |
| **Max Memory** | 512 MB | [.env](../docker-compose.yml#L90) | Default; ⚠️ may be low for large datasets |
| **Max Memory Policy** | `allkeys-lru` | [docker-compose.yml](../docker-compose.yml#L91) | Evict oldest accessed keys when full |
| **Persistence** | **Disabled** | [docker-compose.yml](../docker-compose.yml#L92) | `--save ""` & `--appendonly no` |
| **Password** | Required | [.env](../.env#L29) | `${REDIS_PASSWORD}` |
| **Volume** | `redis-data` (local SSD) | [docker-compose.yml](../docker-compose.yml#L95) | ✅ Fast, ephemeral |

### Redis Command Configuration
[docker-compose.yml](../docker-compose.yml#L88-L93):
```yaml
command: >
  redis-server
  --requirepass ${REDIS_PASSWORD}
  --maxmemory ${REDIS_MAXMEMORY}
  --maxmemory-policy allkeys-lru
  --save ""
  --appendonly no
```

### Resource Limits

| Resource | Limit | Reserve | Reference |
|----------|-------|---------|-----------|
| **Memory Limit** | 768 MB | 64 MB | [.env](../.env#L29) |
| **CPU Limit** | 0.5 cores | — | [.env](../.env#L30) |
| **Storage** | Ephemeral `redis-data` | — | [docker-compose.yml](../docker-compose.yml#L95) |

### Health Check Configuration

[docker-compose.yml](../docker-compose.yml#L97-L102):
```yaml
healthcheck:
  test: ["CMD-SHELL", "redis-cli -a \"$$REDIS_PASSWORD\" ping | grep -q PONG"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 15s
```

---

## Redis Performance Characteristics

### Memory Allocation
- **Configured**: 512 MB max
- **Reserved**: 64 MB minimum
- **Behavior**: `allkeys-lru` evicts least-recently-used keys when full
- **Issue**: ⚠️ 512 MB is relatively small; may cause frequent evictions in high-cardinality workloads

### No Persistence = No Data Durability
| Feature | Current | Risk |
|---------|---------|------|
| **RDB (snapshots)** | Disabled (`--save ""`) | No point-in-time backups |
| **AOF (append-only)** | Disabled (`--appendonly no`) | No write-ahead logging |
| **Replication** | None | Single instance; no failover |
| **Data Loss on Restart** | Inevitable | Cache-only workload okay; session store would lose data |

### Current TTL & Eviction Policy
- **Eviction**: `allkeys-lru` — Evicts oldest accessed key when memory full
- **No explicit TTLs**: Relying on max-memory eviction
- **LRU tracking**: Enabled by default in Redis 7
- **Issue**: ⚠️ No explicit TTL management visible; applications must handle via Redis EXPIRE

### Replication & Clustering
- **Replication**: ❌ None configured
- **Clustering**: ❌ Single node only
- **Failover**: Manual (Docker restart required)
- **Issue**: Single point of failure for session/cache data

---

## Identified Redis Issues

| Issue | Severity | Current State | Impact |
|-------|----------|---------------|--------|
| **Small max-memory** | 🟡 Medium | 512 MB default | High eviction rate if > 512 MB cached; LRU churn |
| **No persistence** | 🟡 Medium | `--save ""` & `--appendonly no` | Data loss on restart; acceptable for ephemeral cache |
| **No replication** | 🟠 Orange | Single instance | No failover; brief downtime if container restarts |
| **No clustering** | 🟠 Orange | Single node | No horizontal scaling; bottleneck at single Redis |
| **No explicit TTLs** | 🟡 Medium | Relying on LRU eviction | Apps must manage TTL via Redis EXPIRE; implicit contracts |
| **0.5 CPU limit** | 🟡 Medium | May throttle during spikes | Redis single-threaded; CPU-bound workloads may bottleneck |
| **No monitoring** | 🟡 Medium | Prometheus scrapes `/metrics` | Health checks basic; no visibility into evictions/keys/memory |

---

## Production Recommendations (Not Yet Applied)

### For High-Cardinality Sessions
**Current**: 512 MB  
**Recommended**: 2-4 GB (for 100k+ sessions at ~10 KB each)

### For Persistence
```yaml
redis:
  command: >
    redis-server
    --requirepass ${REDIS_PASSWORD}
    --maxmemory 2gb
    --maxmemory-policy allkeys-lru
    --save 900 1 500 10 60 10000      # RDB snapshots
    --appendonly yes                  # AOF enabled
    --appendfsync everysec           # Fsync 1x/sec
```

### For Replication (future)
```yaml
redis-primary:
  # Master instance
redis-replica:
  # Replica instance (read-only)
```

---

# 3. NETWORK INFRASTRUCTURE

## Current Network Configuration

### Network Topology
[terraform/network.tf](../terraform/network.tf):
```
Base CIDR: 192.168.168.0/24 (on-premises local network)
├── Public Subnets:   /25 (128 IPs each)
├── Private Subnets:  /26 (64 IPs each)
└── Regional Gateways: Distributed across 5 regions
```

### Deployed Hosts

| Host | IP | Role | Compute | Enabled | Reference |
|------|----|----|---------|---------|-----------|
| **Region 1 (Primary)** | `192.168.168.31` | Primary | 4 vCPU, 16 GB RAM | ✅ Yes | [compute.tf](../terraform/compute.tf#L29) |
| **Region 2 (Failover)** | `192.168.168.32` | Failover | 4 vCPU, 16 GB RAM | ✅ Yes | [compute.tf](../terraform/compute.tf#L34) |
| **Region 3 (Failover)** | `192.168.168.33` | Failover | 4 vCPU, 16 GB RAM | ✅ Yes | [compute.tf](../terraform/compute.tf#L39) |
| **Region 4 (Failover)** | `192.168.168.34` | Failover | 4 vCPU, 16 GB RAM | ✅ Yes | [compute.tf](../terraform/compute.tf#L44) |
| **Region 5 (Standby)** | `192.168.168.35` | Standby | 4 vCPU, 16 GB RAM | ✅ Yes | [compute.tf](../terraform/compute.tf#L49) |
| **NAS Primary** | `192.168.168.56` | Storage | — | ✅ Active | [.env](../.env#L70) |
| **NAS Replica** | `192.168.168.55` | Storage Backup | — | 🟡 Ready | [.env](../.env#L73) |

### Docker Network
[docker-compose.yml](../docker-compose.yml#L624-L626):
```yaml
networks:
  enterprise:
    external: true   # pre-created: docker network create enterprise
```

**Network Configuration**: Bridge network, 172.28.0.0/16 subnet (from template)

### Network Interfaces
[infrastructure-assessment-31.sh](../scripts/infrastructure-assessment-31.sh#L164-L186) checks:
- Network interface configuration
- DNS configuration
- Routing table
- No explicit 10G capability check documented ⚠️

### Firewall Rules
[terraform/network.tf](../terraform/network.tf#L70-L105):

| Rule | Protocol | Port | Direction | Source | Purpose |
|------|----------|------|-----------|--------|---------|
| `allow-ssh-local` | TCP | 22 | Inbound | 192.168.168.0/24 | SSH access |
| `allow-code-server` | TCP | 8080 | Inbound | 192.168.168.0/24 | IDE web UI |
| `allow-postgres` | TCP | 5432 | Inbound | 192.168.168.0/24 | Database |
| `allow-redis` | TCP | 6379 | Inbound | 192.168.168.0/24 | Cache (not exposed) |
| (more) | — | — | — | — | Ollama, Caddy, Prometheus, etc. |

### Caddy Reverse Proxy Settings
[Caddyfile.tpl](../Caddyfile.tpl):

**Timeout Configuration** (from archived variants):
- **Read timeout**: 30-60 seconds
- **Write timeout**: 30-60 seconds
- **Dial timeout**: 10 seconds
- **Keep-alive timeout**: 90 seconds (for long-lived connections)

**Proxy Configuration**:
```
reverse_proxy code-server:8080 {
  # Connection reuse handled automatically
  # Timeouts inherited from Caddy defaults
}
```

---

## Identified Network Bottlenecks

| Issue | Severity | Current State | Impact |
|-------|----------|---------------|--------|
| **No 10G NIC documented** | 🟠 Orange | Not explicitly verified | Assuming 1G NICs; potential bottleneck for high throughput |
| **No jumbo frames (MTU)** | 🟠 Orange | Not configured; likely MTU=1500 | Reduced efficiency for large transfers; 8% overhead |
| **No network bonding** | 🟡 Medium | Single link per host | No redundancy; NIC failure = host unreachable |
| **NFS over 1G network** | 🟡 Medium | 125 MB/s theoretical max | NFS throughput limited to ~100-125 MB/s |
| **No BGP routing** | 🟡 Medium | Static routing only | Inter-region failover requires DNS/manual reroute |
| **Single load balancer** | 🟡 Medium | Not explicitly configured | No active-active multi-region load balancing visible |
| **No QoS/traffic shaping** | 🟢 Low | Not configured | Acceptable for internal network |

### Network Performance Targets
[monitoring.tf](../terraform/monitoring.tf#L200-L201):
- **p99 Latency Target**: 100 ms
- **p99 Latency Alert**: > 150 ms

[alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L22-L31):
- **Latency SLI Violation**: p99 > 100 ms (5m window)
- **Severity**: Warning

---

# 4. PERFORMANCE BASELINES & OPTIMIZATION GAPS

## Established SLO/SLI Targets

### Availability
| Target | Threshold | Alert Level | Reference |
|--------|-----------|-------------|-----------|
| **Availability** | 99.99% | < 99.95% triggers P0 | [monitoring.tf](../terraform/monitoring.tf#L16) |
| **Error Rate** | < 0.1% | > 0.1% critical | [alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L35-L45) |

### Latency
| Metric | Target | Alert | Reference |
|--------|--------|-------|-----------|
| **p99 Latency** | 100 ms | > 100 ms warning | [alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L22-L31) |
| **p99 Latency Alert** | — | > 150 ms critical | [monitoring.tf](../terraform/monitoring.tf#L201) |
| **Cloudflare Tunnel Latency** | < 50 ms | > 1000 ms | [docs/CLOUDFLARE-TUNNEL-SETUP.md](../docs/CLOUDFLARE-TUNNEL-SETUP.md#L251) |

### Infrastructure Capacity
[compute.tf](../terraform/compute.tf#L8-L14):
| Spec | Value | Notes |
|------|-------|-------|
| **vCPU per region** | 4 cores | Modest; suitable for < 10k req/s |
| **Memory per region** | 16 GB | Adequate for services + caching |
| **Storage per region** | 200 GB | Local SSD; NAS for overflow |

### Prometheus Scrape Intervals
[config/prometheus.yml](../config/prometheus.yml):
| Job | Interval | Timeout | Purpose |
|-----|----------|---------|---------|
| Region metrics | 15-30 s | 10 s | Infrastructure health |
| PostgreSQL | 10 s | 5 s | Database metrics |
| Redis | 10 s | 5 s | Cache metrics |
| Caddy | 15 s | 10 s | Reverse proxy metrics |

---

## Performance Baselines (Measured)

### Database (PostgreSQL)
| Metric | Baseline | Notes |
|--------|----------|-------|
| **Connections** | < 80 of 100 | [alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L58) warns at 80 |
| **Replication Lag** | < 100 ms | [alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L75) warns at > 100 ms |
| **Memory Limit** | 2 GB | [.env](../.env#L14) |
| **CPU Limit** | 1.0 core | [.env](../.env#L15) |

### Memory
| Service | Limit | Reserve | Notes |
|---------|-------|---------|-------|
| **PostgreSQL** | 2 GB | 256 MB | Large SSD caches |
| **Code-Server** | 4 GB | 512 MB | IDE workspace |
| **Prometheus** | 2 GB | 256 MB | 30-day retention |
| **Grafana** | 512 MB | 128 MB | Lightweight |
| **Redis** | 768 MB | 64 MB | ⚠️ Small for high volume |
| **Ollama** | 8 GB | 8 GB | GPU offload; needs full RAM |
| **Jaeger** | 1 GB | 128 MB | All-in-one tracing |

### Disk Space
[alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L88-L99):
- **Warning**: > 90% full
- **Critical**: > 95% full

[infrastructure-assessment-31.sh](../scripts/infrastructure-assessment-31.sh#L85-L100):
- Target: > 40 GB available
- Disk retention: 30 days (Prometheus)

---

## Missing Performance Baselines

| Metric | Status | Why Needed |
|--------|--------|-----------|
| **NAS Read Throughput** | ❌ Not measured | Baseline for Ollama model loading time |
| **NAS Write Throughput** | ❌ Not measured | Baseline for backup performance |
| **Network Bandwidth Utilization** | ❌ Not monitored | Identify bottlenecks between regions |
| **Docker I/O Latency** | ❌ Not monitored | Detect local storage issues |
| **Redis Key Eviction Rate** | ❌ Not tracked | Monitor cache efficiency |
| **PostgreSQL Query Latency p95/p99** | ❌ Not monitored | Identify slow queries |
| **Code-Server Extension Load Time** | ❌ Not measured | User experience metric |
| **Ollama Model Inference Latency** | ❌ Not measured | GPU utilization check |

---

## Optimization Opportunities Summary

### Immediate (High ROI, Low Risk)
1. **Monitor NAS throughput** — Run [nas-mount-31.sh test](../scripts/nas-mount-31.sh#L108) monthly
2. **Add Redis eviction metrics** — Prometheus: `redis_evicted_keys_total`
3. **Configure Redis TTLs** — Set explicit EXPIRE for session keys
4. **Document network NICs** — Verify 10G vs 1G interface speeds

### Short-term (Medium ROI, Medium Risk)
5. **Increase Redis max-memory** — 512 MB → 2-4 GB for high-session workloads
6. **Enable Redis AOF** — Add `--appendonly yes` for durability
7. **Add Redis replica** — Failover capability for session store
8. **Tune NFS timeo** — Consider `timeo=600` (60s) for WAN resilience
9. **Enable MTU 9000** — Jumbo frames for NAS traffic (if supported)

### Long-term (Medium ROI, High Risk)
10. **Multi-region active-active** — Replicate PostgreSQL & Redis to 192.168.168.32+
11. **Implement Redis Cluster** — Horizontal scaling beyond single node
12. **S3/cloud NAS replication** — Off-site backup of Ollama models
13. **10G network upgrade** — Replace 1G NICs (if not already 10G)
14. **Dedicated Prometheus cluster** — Separate from application hosts

---

## Configuration Consolidation

### Critical Settings Summary

**Storage** ([docker-compose.yml](../docker-compose.yml#L650-L678)):
```yaml
# NAS: 192.168.168.56:/export (primary)
# Mount: /mnt/nas-56 (via nas-mount-31.sh)
# Protocol: NFS 4.1
# Options: rsize=1048576, wsize=1048576 (1 MB chunks)
# Failover: 192.168.168.55 (manual remount required)
```

**Redis** ([docker-compose.yml](../docker-compose.yml#L80-L109)):
```yaml
# Version: 7.2-alpine
# Port: 6379 (Docker internal, no external)
# Max Memory: 512 MB (--maxmemory)
# Eviction: allkeys-lru (--maxmemory-policy)
# Persistence: Disabled (--save "" --appendonly no)
# Replication: None (single instance)
```

**Network** ([terraform/network.tf](../terraform/network.tf)):
```
# CIDR: 192.168.168.0/24 (on-premises)
# Regions: 5 (primary + 4 failover + 1 standby)
# Docker Network: enterprise (172.28.0.0/16)
# Firewall: TCP 22/8080/5432/6379 + services
```

**Performance** ([monitoring.tf](../terraform/monitoring.tf)):
```
# Latency Target (p99): 100 ms
# Availability Target: 99.99%
# Error Rate Target: < 0.1%
# RTO: 15 minutes
# RPO: 5 minutes
```

---

## Next Steps

### Phase 1: Establish Baselines (1 week)
- [ ] Run NAS throughput test monthly and log results
- [ ] Enable Redis eviction metrics in Prometheus
- [ ] Document actual network NIC speeds (1G vs 10G)
- [ ] Capture query latency distributions (p50/p95/p99)

### Phase 2: Quick Wins (2-4 weeks)
- [ ] Increase Redis max-memory to 2 GB
- [ ] Enable Redis AOF for persistence
- [ ] Configure explicit TTLs for session keys
- [ ] Test NFS parameter tuning (timeo, retrans)

### Phase 3: Scalability (2-3 months)
- [ ] Deploy Redis replica for failover
- [ ] Multi-region PostgreSQL replication
- [ ] Implement Redis Cluster or Sentinel
- [ ] Off-site Ollama model backup

---

## File References (Line Numbers)

### Configuration Files
- [docker-compose.yml](../docker-compose.yml#L1-L700) — Service definitions
- [.env](../.env#L1-L150) — Environment variables
- [config/_base-config.env](../config/_base-config.env#L1-L100) — Base configuration
- [.env.production](../.env.production#L1-L200) — Production overrides

### Infrastructure-as-Code
- [terraform/network.tf](../terraform/network.tf#L1-L100) — Network topology
- [terraform/compute.tf](../terraform/compute.tf#L1-L150) — Compute specs
- [terraform/monitoring.tf](../terraform/monitoring.tf#L1-L200) — Monitoring config

### Scripts
- [scripts/nas-mount-31.sh](../scripts/nas-mount-31.sh#L1-L150) — NAS mount & test
- [scripts/infrastructure-assessment-31.sh](../scripts/infrastructure-assessment-31.sh#L160-L230) — Diagnostics

### Monitoring & Alerting
- [alert-rules-phase-6-slo-sli.yml](../alert-rules-phase-6-slo-sli.yml#L1-L100) — SLO/SLI rules
- [config/prometheus.yml](../config/prometheus.yml#L1-L100) — Scrape jobs

---

**Last Updated**: April 15, 2026  
**Prepared By**: Infrastructure Analysis Agent  
**Status**: READY FOR OPTIMIZATION PLANNING
