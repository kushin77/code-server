# START HERE - LOCAL DEPLOYMENT GUIDE
## Single-Host Production on 192.168.168.31

**Status:** READY TO DEPLOY  
**Timeline:** 4 weeks from now to production  
**Target Host:** 192.168.168.31 (Linux VM)  
**Scope:** Local-first infrastructure, no cloud dependencies initially

---

## The Plan (TL;DR)

We're deploying a production-grade 13-service system on a single Linux host (192.168.168.31) over 4 weeks:

**Week 1:** Infrastructure setup (Docker, storage, networking)  
**Week 2:** Credential management (Vault) + security hardening  
**Week 3:** Deploy all 13 microservices  
**Week 4:** Validation, testing, hardening, go-live  

**After deployment:** 99.9% SLA, ~45 min/month downtime allowed, auto-restart on failures

---

## What You're Getting

✅ **13-Service Architecture**
```
┌──────────────────────────────────────┐
│ Caddy (reverse proxy, TLS 1.3)       │
├──────────────────────────────────────┤
│ App Layer:        Code-Server + Ollama│
│ Security:         Vault + OAuth2     │
│ Observability:    Prometheus + Jaeger│
│ Logging:          Elasticsearch + Kibana
│ Alerting:         AlertManager       │
│ Data:             PostgreSQL + Redis │
│ Monitoring:       Node-Exporter      │
└──────────────────────────────────────┘
```

✅ **Enterprise Features**
- TLS 1.3 encryption (OCSP stapling)
- Hardware-grade audit logging (2-year GDPR retention)
- Vault-managed secrets (no hardcoded credentials)
- OAuth2 + Duo MFA authentication
- Multi-tier observability (metrics, traces, logs)
- Automatic service restart on failure
- Local backup/restore (5-min RPO, 15-min RTO)
- Compliance-ready (SOC2, HIPAA, GDPR framework)

✅ **Operational Tools**
- Deployment checklists (300+ verification items)
- Incident response runbooks (6 common scenarios)
- Performance testing procedures
- Backup validation procedures

---

## Quick Start (Choose Your Role)

### For DevOps/Infrastructure Person
**You're responsible for:** Provisioning, deployment, ongoing operations

1. Read: [LOCAL-DEPLOYMENT-FOCUS.md](LOCAL-DEPLOYMENT-FOCUS.md) (30 min)
   - Understand what's local vs cloud
   - See 4-week timeline
   - Know scope boundaries

2. Use: [LOCAL-DEPLOYMENT-CHECKLIST.md](LOCAL-DEPLOYMENT-CHECKLIST.md) (follow week-by-week)
   - Phase 1: Infrastructure setup
   - Phase 2: Vault + security
   - Phase 3: Deploy services
   - Phase 4: Validation & hardening

3. Have Ready: [LOCAL-INCIDENT-RESPONSE.md](LOCAL-INCIDENT-RESPONSE.md) (for emergencies)
   - Know how to handle service outages
   - Understand recovery procedures
   - Reference 7 common scenarios

### For Security/Compliance Person
**You're responsible for:** Secrets management, compliance, audit

1. Review: [LOCAL-DEPLOYMENT-FOCUS.md](LOCAL-DEPLOYMENT-FOCUS.md) → Security section
2. Check: Service configurations
   - [Caddyfile.production](Caddyfile.production) - TLS, CSP, security headers
   - [.env.production](.env.production) - Vault secret pattern
   - [postgres-init.sql](postgres-init.sql) - RBAC, audit schema

3. Validate (using checklist Phase 4):
   - No hardcoded secrets
   - TLS working (A+ SSL Labs)
   - Audit logging functional
   - Access controls in place

### For Operations/On-Call Person
**You're responsible for:** Running the system, incident response

1. Quick read: [LOCAL-INCIDENT-RESPONSE.md](LOCAL-INCIDENT-RESPONSE.md) (20 min)
2. Learn: Common scenarios + recovery steps
3. Bookmark: Quick command reference
4. Test: Practice response (Phase 4 of checklist)

### For Project Manager
**You're responsible for:** Timeline, sign-offs, coordination

1. Read: [LOCAL-DEPLOYMENT-FOCUS.md](LOCAL-DEPLOYMENT-FOCUS.md) → Timeline section
2. Use: [LOCAL-DEPLOYMENT-CHECKLIST.md](LOCAL-DEPLOYMENT-CHECKLIST.md) → Sign-off section
3. Track: Phase completion (5 phases over 4 weeks)
4. Coordinate: Team assignments per phase

---

## File Guide (Which Doc to Read?)

### Strategic Documents (Plan & Architecture)

| Document | Purpose | When to Read |
|----------|---------|--------------|
| [LOCAL-DEPLOYMENT-FOCUS.md](LOCAL-DEPLOYMENT-FOCUS.md) | Define scope: local vs cloud, timeline, architecture | **First** - understanding phase |
| [ENTERPRISE-PRODUCTION-DEPLOYMENT.md](ENTERPRISE-PRODUCTION-DEPLOYMENT.md) | Full enterprise architecture specification | Reference, skip multi-region sections |
| [PRODUCTION-ASSET-INDEX.md](PRODUCTION-ASSET-INDEX.md) | Index of all files + dependencies | Navigation guide |

### Operational Documents (Do This)

| Document | Purpose | When to Use |
|----------|---------|------------|
| [LOCAL-DEPLOYMENT-CHECKLIST.md](LOCAL-DEPLOYMENT-CHECKLIST.md) | Week-by-week deployment checklist (Phase 1-5) | **Follow week-by-week** - actual deployment |
| [ENTERPRISE-PRODUCTION-DEPLOYMENT-GUIDE.md](ENTERPRISE-PRODUCTION-DEPLOYMENT-GUIDE.md) | Detailed week-by-week guide with commands | Reference for step-by-step instructions |
| [PRODUCTION-DEPLOYMENT-CHECKLIST.md](PRODUCTION-DEPLOYMENT-CHECKLIST.md) | Advanced multi-phase checklist (skip cloud sections) | Skip multi-region sections |

### Emergency Documents (Help!)

| Document | Purpose | When to Use |
|----------|---------|------------|
| [LOCAL-INCIDENT-RESPONSE.md](LOCAL-INCIDENT-RESPONSE.md) | Emergency runbook for 7 common scenarios | **During incidents** - fast recovery |
| [PRODUCTION-INCIDENT-RESPONSE.md](PRODUCTION-INCIDENT-RESPONSE.md) | Comprehensive incident guide | Reference, skip cloud failover |

### Configuration Documents (Deploy These)

| File | Purpose | Used In |
|------|---------|---------|
| [docker-compose.production.yml](docker-compose.production.yml) | 13-service orchestration | Week 3 deployment |
| [Caddyfile.production](Caddyfile.production) | Reverse proxy + TLS config | Week 3 deployment |
| [.env.production](.env.production) | Environment variables (Vault references) | Week 2 secret setup + deployment |
| [prometheus-production.yml](prometheus-production.yml) | Metrics collection config | Week 3 deployment |
| [alertmanager-production.yml](alertmanager-production.yml) | Alert routing config | Week 3 deployment |
| [postgres-init.sql](postgres-init.sql) | Database initialization | Week 3 deployment |

---

## 30-Second Overview

**What:** Production Docker Compose deployment on Linux host
**Where:** 192.168.168.31 (single VM)
**When:** 4 weeks (Week 1-4)
**Who:** DevOps, Security, Operations, PM
**Why:** Enterprise-grade but local-first (simpler + faster)
**How:** Follow LOCAL-DEPLOYMENT-CHECKLIST.md phase by phase

**Now vs Later:**
- ✅ Local single-host deployment (now)
- ⏸️ Multi-region failover (later, Phase 2)
- ⏸️ Cloud managed services (later, Phase 2+)
- ⏸️ Kubernetes (later, Phase 3+)

---

## Week-by-Week Summary

### Week 1: Infrastructure (5 days)
**Goal:** Prepare Linux host for deployment

Checklist: [LOCAL-DEPLOYMENT-CHECKLIST.md → Phase 1](LOCAL-DEPLOYMENT-CHECKLIST.md)
- [ ] Verify 8+ CPU, 32+ GB RAM, 500+ GB SSD
- [ ] Install Docker + Docker Compose
- [ ] Create /data directory (500GB)
- [ ] Configure local DNS (workspace.local)
- [ ] Create Docker network

**Deliverable:** Bare host ready for deployment

### Week 2: Credentials & Security (7 days)
**Goal:** Set up Vault and load secrets

Checklist: [LOCAL-DEPLOYMENT-CHECKLIST.md → Phase 2](LOCAL-DEPLOYMENT-CHECKLIST.md)
- [ ] Deploy Vault container
- [ ] Initialize Vault (get 5 unseal keys)
- [ ] Load secrets: OAuth, DB passwords, API keys
- [ ] Create .env file with Vault references
- [ ] Validate no hardcoded secrets

**Deliverable:** Secure credential management operational

### Week 3: Deployment (7 days)
**Goal:** Deploy all 13 services

Checklist: [LOCAL-DEPLOYMENT-CHECKLIST.md → Phase 3](LOCAL-DEPLOYMENT-CHECKLIST.md)
- [ ] Start PostgreSQL + Redis (Tier 5 - data)
- [ ] Start Vault + OAuth2 (Tier 3a - security)
- [ ] Start observability stack (Tier 3b)
- [ ] Start Code-Server + Ollama (Tier 4 - apps)
- [ ] Verify all 13 healthy

**Deliverable:** All services running locally

### Week 4: Validation (4 days)
**Goal:** Harden, test, validate, go-live

Checklist: [LOCAL-DEPLOYMENT-CHECKLIST.md → Phase 4 & 5](LOCAL-DEPLOYMENT-CHECKLIST.md)
- [ ] Security audit: no hardcoded secrets, TLS valid
- [ ] Performance test: p99 < 500ms sustained
- [ ] Load test: 100 req/sec without errors
- [ ] Backup/restore test: verify recovery works
- [ ] Final sign-offs

**Deliverable:** Production-ready system live

---

## Command Reference (Quick Copy-Paste)

```bash
# SSH to host
ssh akushnir@192.168.168.31

# Check everything is running
docker-compose ps

# View all logs
docker-compose logs --tail=50

# Restart a service
docker-compose restart code-server

# Check resource usage
docker stats --no-stream

# Simple load test
ab -n 1000 -c 50 http://localhost/health

# Emergency: restart everything
docker-compose down && sleep 10 && docker-compose up -d && sleep 30 && docker-compose ps

# Check disk space
df -h /data
```

---

## Common Questions

**Q: Why local-first instead of cloud?**
A: Faster deployment, simpler setup, easier debugging, lower cost initially. Can add multi-region later.

**Q: How long until production?**
A: 4 weeks if you follow the phases sequentially. Shorter if you work in parallel.

**Q: What if something breaks during deployment?**
A: Use [LOCAL-INCIDENT-RESPONSE.md](LOCAL-INCIDENT-RESPONSE.md) for diagnosis and recovery steps.

**Q: What happens if the host goes down?**
A: Auto-restart brings services back (containers use restart policy). Restore from backup if data lost.

**Q: Can I add a second host later?**
A: Yes. After Phase 1 validated, Phase 2 covers adding warm standby. But not now.

**Q: What if I need cloud integration?**
A: Phase 3 in future. For now, stay local.

**Q: Who do I contact if stuck?**
A: - Week 1 issues: DevOps lead
- Week 2 security issues: Security engineer
- Operational issues: On-call (use incident runbook)

---

## Success Criteria

✅ **Deployment successful when:**
- All 13 services show "Up" or "healthy" in `docker-compose ps`
- Users can access Code-Server via https://workspace.local
- No recent errors in logs (< 3 errors in last 10 minutes)
- Disk usage < 80%
- Backup exists and can be restored
- All 5 phases signed off

✅ **Live to production when:**
- All phases + all checklists complete
- Team trained on incident response
- Status monitoring in place
- First backup validated

---

## Next Actions (Right Now)

1. **Read first:** [LOCAL-DEPLOYMENT-FOCUS.md](LOCAL-DEPLOYMENT-FOCUS.md) (30 min)
2. **Review checklists:** [LOCAL-DEPLOYMENT-CHECKLIST.md](LOCAL-DEPLOYMENT-CHECKLIST.md) (overview)
3. **Assign responsibilities:**
   - DevOps lead → Deployment
   - Security → Phase 2 credentials
   - Operations → Incident response training
   - PM → Timeline tracking
4. **Verify host ready:** 8+ CPU, 32+ GB RAM, 500+ GB SSD
5. **Schedule kicks-off:** Week 1 start date

---

## Status

✅ **Documentation:** Complete  
✅ **Configuration Files:** Complete  
✅ **Runbooks:** Complete  
⏳ **Infrastructure:** Ready (needs assignment)  
⏳ **Deployment:** Waiting to start Week 1  
⏳ **Go-Live:** Targeting Week 5 (4 weeks after start)

---

📚 **Start with:** [LOCAL-DEPLOYMENT-FOCUS.md](LOCAL-DEPLOYMENT-FOCUS.md)  
📋 **Then follow:** [LOCAL-DEPLOYMENT-CHECKLIST.md](LOCAL-DEPLOYMENT-CHECKLIST.md)  
🆘 **If emergency:** [LOCAL-INCIDENT-RESPONSE.md](LOCAL-INCIDENT-RESPONSE.md)

