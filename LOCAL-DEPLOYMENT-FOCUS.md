# LOCAL-FIRST DEPLOYMENT STRATEGY
## Focusing on 192.168.168.31 Single-Host Deployment

**Status:** ACTIVE SCOPE  
**Date:** 2026-04-13  
**Focus:** Local infrastructure only (192.168.168.31)  
**Cloud Tasks:** DEFERRED (marked for future phases)

---

## Current Scope - LOCAL ONLY

### What We're Keeping ACTIVE

✅ **Single-Host Deployment (192.168.168.31)**
- Docker Compose on one Linux VM
- Local persistent storage (/data/*)
- Internal networking (10.0.8.0/24)
- Local PostgreSQL, Redis, Vault
- No external cloud dependencies

✅ **Local Security & Operations**
- HashiCorp Vault (local instance)
- OAuth2 authentication (local)
- Local Prometheus + Jaeger + ELK
- Local incident response (no cloud failover)
- Local backup storage

✅ **Production-Grade Features (Kept)**
- 13-service Docker Compose architecture
- Enterprise security (TLS 1.3, RBAC, audit logs)
- Multi-tier observability
- Disaster recovery (single-host backup/restore)
- Compliance framework documentation

---

## What We're DEFERRING - Cloud-Specific Tasks

### DEFER: Multi-Region Setup
- ❌ GCP regional infrastructure provisioning
- ❌ AWS multi-AZ deployment
- ❌ Azure region failover
- ❌ Cross-region replication
- ❌ Global load balancing (CloudFlare active-active)
- ⏸️ **DEFER TO:** Phase 2 (after single-host validated)

### DEFER: Managed Cloud Services
- ❌ Cloud SQL (use local PostgreSQL)
- ❌ Cloud Memorystore Redis (use local Redis)
- ❌ Cloud KMS (use local Vault)
- ❌ Cloud Logging (use local ELK)
- ❌ Cloud Monitoring (use local Prometheus)
- ⏸️ **DEFER TO:** Phase 2

### DEFER: Cloud CI/CD Integration
- ❌ Terraform cloud provisioning
- ❌ GitHub Actions cloud deployment
- ❌ Cloud artifact registry (Cloud Build)
- ❌ Kubernetes cluster management
- ⏸️ **DEFER TO:** Phase 3

### DEFER: Advanced HA Features
- ❌ Multi-region active-active failover
- ❌ Cross-region traffic routing
- ❌ Distributed consensus (etcd, Zookeeper)
- ⏸️ **DEFER TO:** Phase 2 (when adding second region)

---

## Adjusted Timeline - LOCAL ONLY

### Week 1: Infrastructure Setup (LOCAL)
```bash
Target: 192.168.168.31 only

Day 1-2: Verify host is ready
  ✅ 8+ CPU cores
  ✅ 32+ GB RAM
  ✅ 500+ GB SSD
  ✅ Docker 20.10+ installed
  ✅ Docker Compose 2.10+ installed

Day 3: Create persistent storage
  ✅ mkdir /data/{postgres,redis,ollama,prometheus,elasticsearch}
  ✅ Set permissions (1000:1000)
  ✅ Verify disk space (df -h /data)

Day 4-5: Network setup
  ✅ Create Docker bridge network (10.0.8.0/24)
  ✅ Configure DNS locally (/etc/hosts)
  ✅ Test local connectivity

Result: Single host ready for deployment
```

### Week 2: Credential & Security Setup (LOCAL VAULT)
```bash
Day 8-9: HashiCorp Vault deployment
  ✅ Start Vault container (single instance)
  ✅ Initialize Vault (local only, not HA)
  ✅ Load all secrets into Vault
  ✅ Store root token securely

Day 10-11: Load secrets
  ✅ Cloudflare API token (if using for DNS only)
  ✅ Google OAuth credentials
  ✅ Database passwords
  ✅ SSH keys

Day 12-14: Security hardening (local)
  ✅ TLS certificate setup (local or self-signed)
  ✅ Vault audit logging
  ✅ No exposed credentials

Result: Vault operational with all secrets loaded
```

### Week 3: Application Deployment (LOCAL)
```bash
Day 15-21: Deploy 13-service stack
  ✅ PostgreSQL (single instance)
  ✅ Redis (single instance)
  ✅ Vault (single instance)
  ✅ OAuth2-Proxy (local)
  ✅ Caddy reverse proxy (local)
  ✅ Code-Server (local)
  ✅ Ollama (local)
  ✅ Prometheus (local)
  ✅ Elasticsearch + Kibana (local)
  ✅ Jaeger (local)
  ✅ AlertManager (local)

Result: All 13 services healthy on 192.168.168.31
```

### Week 4: Validation & Hardening (LOCAL)
```bash
Day 22-25: Comprehensive testing
  ✅ Security audit (no hardcoded secrets)
  ✅ Performance testing (p95 < 200ms)
  ✅ Load testing (100 req/sec sustained)
  ✅ Backup/restore validation
  ✅ Service interdependency testing

Result: Production-ready single-host system
```

**Total: 4 weeks to operational single-host deployment**

---

## Local SLA Targets (Single-Host)

| Metric | Target | Notes |
|--------|--------|-------|
| Availability | 99.9% (3 nines) | Single host, but with auto-restart |
| MTTD | < 1 minute | AlertManager on host |
| MTTR | < 5 minutes | Auto-restart + manual recovery |
| p95 Latency | < 200ms | All local, no network latency |
| p99 Latency | < 500ms | Expected with local I/O |
| Error Rate | < 0.1% | No cross-region issues |
| RTO | < 15 min | Container restart + restore |
| RPO | < 5 min | Local snapshots every 5 min |

---

## Local Deployment Checklist (Updated)

### Phase 1: Pre-Deployment ✅
- [x] 192.168.168.31 provisioned
- [x] Docker + Docker Compose installed
- [x] Network connectivity verified
- [x] SSH access confirmed
- [ ] Disk space verified (>500GB)
- [ ] RAM available (32GB)
- [ ] CPU cores available (8+)

### Phase 2: Credentials Setup (Week 2)
- [ ] Vault container started
- [ ] Vault initialized (local)
- [ ] OAuth credentials loaded
- [ ] Database passwords stored
- [ ] Certificates ready (local)
- [ ] No cloud dependencies needed

### Phase 3: Deployment (Week 3)
- [ ] Data layer: PostgreSQL + Redis (local)
- [ ] Security: Vault + OAuth2 (local)
- [ ] Observability: Prometheus + ELK (local)
- [ ] Applications: Code-Server + Ollama (local)
- [ ] All 13 services healthy
- [ ] Network connectivity verified

### Phase 4: Validation (Week 4)
- [ ] Security audit passed
- [ ] Performance targets met
- [ ] Load test successful
- [ ] Backup/restore working
- [ ] Local SLA targets met

### Phase 5: Go-Live
- [ ] All checklists complete
- [ ] Team trained on local operations
- [ ] Incident response tested locally
- [ ] ✅ System live on 192.168.168.31

---

## Adjustments to Deployment Guides

### REMOVE from ENTERPRISE-PRODUCTION-DEPLOYMENT.md
- ❌ Week 1, Day 4: "Multi-region setup" → **SKIP (defer to Phase 2)**
- ❌ Week 1: "Cloud infrastructure provisioning" → **Use existing host**
- ❌ Week 2: "Cloud KMS seal for Vault" → **Use local raft storage**
- ❌ Week 3: "Managed databases" → **Use Docker containers**
- ❌ Week 4: "CloudFlare active-active" → **Use local DNS only**

### KEEP in ENTERPRISE-PRODUCTION-DEPLOYMENT.md
- ✅ 7-tier architecture (local only)
- ✅ 13-service Docker Compose
- ✅ Security hardening (local)
- ✅ Observability stack (local)
- ✅ Disaster recovery (local backup/restore)
- ✅ Compliance framework
- ✅ Incident response (local)

### ADD to Guides
**Section: "Scaling to Multi-Region (Future)"**
- Document how to add second host (192.168.168.32) as warm standby
- Replication procedures (PostgreSQL streaming, Redis replication)
- Failover testing (switch to secondary host)
- Timeline: Phase 2 (after Phase 1 validated)

---

## Issues to Close / Defer

### Close as "Out of Scope (Local-First)"
- [ ] Multi-region GCP setup
- [ ] AWS active-active failover
- [ ] Azure region failover
- [ ] Kubernetes deployment
- [ ] Terraform cloud provisioning
- [ ] CloudFlare advanced WAF rules
- [ ] Cloud cost optimization
- [ ] Multi-region disaster recovery

### Create New Local-Focus Issue (P1)
**Title:** "Single-Host Production Validation (192.168.168.31)"
- Verify all 13 services healthy
- Run performance tests
- Validate backup/restore
- Security audit
- Complete local deployment checklist

### Create for Phase 2 (future P2 issues)
**Title:** "Add Second Host for High Availability (192.168.168.32)"
**Title:** "Implement Multi-Region Failover"
**Title:** "Terraform Cloud Infrastructure"

---

## Local-Only Resources Required

### Network
- Static IP: 192.168.168.31 (already assigned)
- Local DNS: /etc/hosts file (no cloud DNS needed)
- TLS: Self-signed or local CA (not CloudFlare ACME)

### Storage
- Local /data volume (500GB+)
- Optional: NFS mount for backup
- Snapshot tool: restic, duplicacy, or rsync

### Compute
- 8+ CPU cores
- 32+ GB RAM
- 500+ GB SSD (local storage, no cloud volumes)

### Software Stack
- Same 13 services (all containerized, no cloud APIs)
- No external dependencies
- Single namespace (no multi-environment)

---

## Backup Strategy (Local)

```bash
# Daily backup to local NAS or external drive
Daily snapshots:
  - PostgreSQL: pg_dump + gzip (to /backups/)
  - Redis: BGSAVE (to /backups/)
  - Elasticsearch: snapshot API (to /backups/)
  - Application data: rsync -a /data/ /backups/

# Weekly full backup (off-site)
  - tar -czf /backups/week-$(date +%Y%m%d).tar.gz /data/
  - scp to external server or cloud storage (manual for now)

# Monthly validation
  - Test restore on secondary (if available)
  - Verify backup integrity (checksums)
  - Document recovery time
```

---

## Next Steps

### Immediate (This Week)
1. ✅ Update ENTERPRISE-PRODUCTION-DEPLOYMENT-GUIDE.md (remove cloud sections)
2. ✅ Create LOCAL-DEPLOYMENT-CHECKLIST.md (simplified)
3. ✅ Create LOCAL-INCIDENT-RESPONSE.md (no multi-region failover)
4. ✅ Document local backup/restore procedures
5. ⏸️ Close cloud-specific GitHub issues

### Short Term (Weeks 2-4)
1. Provision 192.168.168.31 (if not done)
2. Deploy Vault + all 13 services
3. Run validation tests
4. Go live on local infrastructure
5. Document learnings

### Future (Phase 2, TBD)
1. Add second host for warm standby
2. Implement replication (PostgreSQL, Redis)
3. Test failover procedures
4. Then: Multi-region (if needed)
5. Then: Cloud integration (if needed)

---

## Architecture - Local Only

```
LOCAL SINGLE-HOST DEPLOYMENT
192.168.168.31
===================================

┌──────────────────────────────────────┐
│  Users (local network access)         │
│  via DNS: workspace.local            │
└────────────┬─────────────────────────┘
             │
      ┌──────▼──────┐
      │ Caddy (80/443) Reverse Proxy
      │ TLS: self-signed or local CA
      └──────┬──────┘
             │
      ┌──────────────────────────────┐
      │ Docker Network (10.0.8.0/24) │
      │ 13 Microservices             │
      │                              │
      │ Tier 4: Code-Server + Ollama │
      │ Tier 3: Vault + OAuth + Obs  │
      │ Tier 5: PostgreSQL + Redis   │
      │ Tier 6: Prometheus + ELK     │
      └──────┬──────────────────────┘
             │
      ┌──────▼──────┐
      │ /data/ Volume (500GB+)
      │ - PostgreSQL data
      │ - Redis persistence
      │ - Elasticsearch indices
      │ - Application files
      │ - Backups
      └──────────────┘
```

---

## Local Testing Procedures

```bash
# Daily health check (local)
docker-compose ps  # all 13 should be Up/healthy
docker stats --no-stream  # check resource usage

# Weekly performance test (local)
ab -n 10000 -c 100 http://localhost:80/health

# Monthly backup test (local)
docker-compose exec postgres pg_dump > /tmp/test_backup.sql
# verify file is valid

# Quarterly security audit (local)
grep -r "password\|secret\|token" . | grep -v "{VAULT" | grep -v ".git"
# should find nothing
```

---

## Summary

**What We're Doing:**
- Single-host deployment on 192.168.168.31
- All 13 services containerized locally
- Enterprise security + observability (local)
- 99.9% SLA with local recovery
- 4-week timeline to go-live

**What We're NOT Doing (Yet):**
- Multi-region setup
- Cloud infrastructure (GCP/AWS/Azure)
- Kubernetes orchestration
- Advanced HA (active-active failover)
- Cloud cost optimization

**Timeline:**
- Week 1-4: Single-host production deployment
- Phase 2 (TBD): Add second host for failover
- Phase 3 (TBD): Multi-region if needed
- Phase 4 (TBD): Cloud integration if needed

**Status:** FOCUSED & STREAMLINED ✅

