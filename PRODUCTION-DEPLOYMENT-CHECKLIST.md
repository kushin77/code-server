# PRODUCTION DEPLOYMENT CHECKLIST
## Phase-by-Phase Verification & Sign-off

**Version:** 1.0  
**Status:** ACTIVE  
**Last Updated:** 2026-04-13  

---

## PHASE 1: Pre-Deployment (Week 1, Day 1-5)

### Infrastructure Verification

- [ ] **Compute Resources Allocated**
  - [ ] Primary host: 8+ CPU cores
  - [ ] Primary host: 32+ GB RAM
  - [ ] Primary host: 500+ GB SSD storage
  - [ ] Warm standby provisioned (for HA)
  - [ ] Off-site backup storage configured

- [ ] **Network Configuration**
  - [ ] Public IP address assigned (192.168.168.31)
  - [ ] DNS A record pointing to public IP
  - [ ] CloudFlare configured as edge (DDoS protection)
  - [ ] Security group rules allowing 80/443/22
  - [ ] Internal network subnet configured (10.0.8.0/24)

- [ ] **Software Prerequisites**
  - [ ] Linux kernel 5.10 or newer (check: `uname -r`)
  - [ ] Docker 20.10+ installed (`docker --version`)
  - [ ] Docker Compose 2.10+ installed (`docker-compose --version`)
  - [ ] SSH access verified from jump host
  - [ ] Sudo access confirmed for root operations

### File Preparation

- [ ] **Configuration Files Present**
  - [ ] docker-compose.production.yml copied
  - [ ] Caddyfile.production copied
  - [ ] .env.production template copied
  - [ ] prometheus-production.yml copied
  - [ ] alertmanager-production.yml copied
  - [ ] postgres-init.sql copied

- [ ] **Repository State**
  - [ ] Code cloned from git-rca-workspace
  - [ ] Latest version pulled (`git log -1`)
  - [ ] No uncommitted changes (`git status`)
  - [ ] All config files have correct permissions (644 for files, 755 for directories)

### Team & Access

- [ ] **Personnel Assigned**
  - [ ] DevOps lead identified (on-call rotation)
  - [ ] Security engineer assigned
  - [ ] Database administrator assigned
  - [ ] SRE on-call contact established

- [ ] **Access Credentials Prepared**
  - [ ] SSH key pairs generated (DevOps + Backup team)
  - [ ] Vault root token stored securely (split across 5 team members)
  - [ ] GitHub deployment token created
  - [ ] CloudFlare API token available

**Sign-off:** _______________________ Date: ___________

---

## PHASE 2: Credential & Security Setup (Week 2, Day 8-14)

### HashiCorp Vault Installation

- [ ] **Vault Deployment**
  - [ ] Vault container started successfully
  - [ ] Vault API responding on port 8200
  - [ ] Vault operator initialized (5 keys, 3 threshold)
  - [ ] Vault unsealed with 3 keys
  - [ ] Vault status showing "Initialized: true, Sealed: false"

- [ ] **Secret Engine Configuration**
  - [ ] KV v2 secrets engine enabled at path "secret"
  - [ ] Database secret engine enabled (for password rotation)
  - [ ] PKI secret engine enabled (for cert management)
  - [ ] Audit logging enabled (file backend to /var/log/vault/)

### Production Secrets Loaded

- [ ] **CloudFlare Integration**
  - [ ] API token stored: `secret/production/cloudflare/api-token`
  - [ ] Token verified accessible from Vault CLI
  - [ ] Token has permissions: DNS:edit, SSL/TLS:edit, Cache:edit

- [ ] **Google OAuth Configuration**
  - [ ] Client ID stored: `secret/production/google/oauth`
  - [ ] Client secret stored with OAuth
  - [ ] Redirect URIs configuredin Google Console
  - [ ] Verified: https://ide.kushnir.cloud/oauth2/callback

- [ ] **OAuth2-Proxy Secrets**
  - [ ] Cookie secret (32-byte) stored
  - [ ] Session secret stored
  - [ ] HMAC key stored

- [ ] **Duo Security MFA**
  - [ ] Integration key stored
  - [ ] Secret key stored
  - [ ] API host configured
  - [ ] Test login verified (with own account)

- [ ] **Application Credentials**
  - [ ] Code-Server password (32+ characters) stored
  - [ ] Redis password stored
  - [ ] PostgreSQL password stored
  - [ ] Elasticsearch password stored
  - [ ] GitHub token stored

- [ ] **Integration Secrets**
  - [ ] Slack webhook URL stored
  - [ ] PagerDuty integration key stored
  - [ ] Email SMTP credentials stored

### Environment Configuration

- [ ] **.env File Complete**
  - [ ] All variables reference ${VAULT_*} or ${DOMAIN} (no hardcoded values)
  - [ ] Validated syntax: `grep "^[A-Z_]*=" .env | wc -l` shows 20+ variables
  - [ ] No "CHANGEME" placeholders remaining
  - [ ] File permissions set to 600 (readable only by owner)

- [ ] **TLS Certificate Preparation**
  - [ ] CloudFlare API token tested for DNS-01 verification
  - [ ] Wildcard certificate configuration: *.ide.kushnir.cloud
  - [ ] ACME challenge DNS records prepared
  - [ ] Certificate auto-renewal configured in Caddy

### Security Hardening

- [ ] **Vault Security**
  - [ ] Vault audit logs enabled and flowing
  - [ ] Root token revoked after initialization
  - [ ] Auth methods configured (AppRole, JWT)
  - [ ] Policy for service-to-service auth created

- [ ] **Secret Rotation Policy**
  - [ ] Rotation interval set (90 days for database passwords)
  - [ ] Rotation scripts prepared
  - [ ] Notification system configured (Slack alert on rotation)

**Sign-off:** _______________________ Date: ___________

---

## PHASE 3: Application Deployment (Week 3, Day 15-21)

### Docker Image Preparation

- [ ] **Custom Images Built**
  - [ ] code-server-patched built successfully
  - [ ] ssh-proxy built successfully
  - [ ] Image scan completed: `trivy image code-server-patched`
  - [ ] No HIGH/CRITICAL vulnerabilities (or mitigated)

- [ ] **Pre-built Images Available**
  - [ ] caddy:latest pulled
  - [ ] prometheus:latest pulled
  - [ ] elasticsearch:8.x pulled
  - [ ] postgres:15 pulled
  - [ ] redis:7 pulled
  - [ ] ollama:latest pulled
  - [ ] jaeger:latest pulled

- [ ] **Image Registry**
  - [ ] Private registry configured (for air-gapped environments)
  - [ ] Image manifest verified: `docker-compose images`
  - [ ] All images present and correct size

### Data Layer Initialization (Tier 5)

- [ ] **PostgreSQL**
  - [ ] Container started: `docker-compose up -d postgres`
  - [ ] Health check passing: `docker-compose exec postgres pg_isready`
  - [ ] postgres-init.sql applied: `psql -f postgres-init.sql`
  - [ ] Schemas created: audit, sessions, config, workspace, rbac, monitoring
  - [ ] Users created: ide_app, ide_readonly, ide_audit
  - [ ] Replication user configured (for warm standby)
  - [ ] Backups scheduled (daily, retained 30 days)

- [ ] **Redis**
  - [ ] Container started: `docker-compose up -d redis`
  - [ ] Health check passing: `docker-compose exec redis redis-cli ping`
  - [ ] Persistence configured (AOF + RDB snapshots)
  - [ ] Memory limit set (70% of available RAM)
  - [ ] Eviction policy: allkeys-lru

- [ ] **Storage Volumes**
  - [ ] /data/postgres directory mounted and accessible
  - [ ] /data/redis directory mounted and accessible
  - [ ] /data/ollama directory mounted and accessible
  - [ ] /data/prometheus directory mounted and accessible
  - [ ] /data/elasticsearch directory mounted and accessible
  - [ ] All directories owned by correct UID (1000)
  - [ ] Backup snapshots configured for all volumes

### Security & Auth Layer (Tier 3a)

- [ ] **Vault Integration**
  - [ ] Vault container healthy: `docker-compose exec vault vault status`
  - [ ] All secrets accessible via Vault API
  - [ ] Unsealing procedure documented and tested

- [ ] **OAuth2-Proxy**
  - [ ] Container started
  - [ ] Logs show no configuration errors
  - [ ] Health check accessible: `curl http://localhost:4180/ping`
  - [ ] Google OAuth flow tested (personal account)
  - [ ] MFA flow tested (Duo)
  - [ ] Session cookies encrypted (EncryptedData in response)

### Observability Stack (Tier 3b)

- [ ] **Prometheus**
  - [ ] Container healthy
  - [ ] Web UI accessible on http://localhost:9090
  - [ ] All 10 scrape jobs configured
  - [ ] Metrics flowing: `curl 'http://localhost:9090/api/v1/targets'`
  - [ ] Retention set to 365 days
  - [ ] Storage usage < 10% of disk

- [ ] **Elasticsearch**
  - [ ] Cluster initialized (single node OK for non-prod)
  - [ ] Health: `curl http://localhost:9200/_cluster/health`
  - [ ] Shows "green" status
  - [ ] Indices created for application logs
  - [ ] Index lifecycle management configured (hot/warm/cold)

- [ ] **Kibana**
  - [ ] Web UI accessible on http://localhost:5601
  - [ ] Elasticsearch datasource connected
  - [ ] Default index pattern configured
  - [ ] Log viewer showing application logs

- [ ] **Jaeger**
  - [ ] Web UI accessible on port 16686
  - [ ] Collector receiving spans
  - [ ] Storage backend configured (elasticsearch or badger)
  - [ ] Sampling configured (tail-based, 20%)

- [ ] **AlertManager**
  - [ ] Container healthy
  - [ ] Alert receiver configuration valid
  - [ ] Slack integration tested (send test alert)
  - [ ] PagerDuty integration tested
  - [ ] Email digest configured

### Application Services (Tier 4)

- [ ] **Caddy Reverse Proxy**
  - [ ] Container healthy
  - [ ] HTTPS certificate obtained (via CloudFlare DNS-01)
  - [ ] Certificate valid: `openssl s_client -connect localhost:443`
  - [ ] All domains resolving: curl -L https://ide.kushnir.cloud/health
  - [ ] Rate limiting active (test with: `ab -n 1100 ...` should get 429s)
  - [ ] Security headers present (HSTS, CSP, X-Frame-Options)

- [ ] **Code-Server**
  - [ ] Container healthy
  - [ ] Web UI accessible at https://ide.kushnir.cloud
  - [ ] OAuth redirects working
  - [ ] Terminal functional
  - [ ] File editing working
  - [ ] Extensions loading

- [ ] **Ollama LLM Service**
  - [ ] Container started
  - [ ] Model downloaded (`ollama pull llama2`)
  - [ ] API responding: `curl http://localhost:11434/api/tags`
  - [ ] Model inference tested with sample prompt
  - [ ] GPU acceleration verified (if available)

- [ ] **SSH Proxy**
  - [ ] Container healthy
  - [ ] SSH handshake working
  - [ ] Port forwarding configured
  - [ ] Bastion functionality verified

- [ ] **Monitoring Agents**
  - [ ] Node-Exporter running (port 9100)
  - [ ] cAdvisor running (port 8080)
  - [ ] Metrics flowing to Prometheus

### Service Mesh Verification

- [ ] **All Services Communicating**
  - [ ] Code-Server → Ollama: request succeeds
  - [ ] Code-Server → Redis: session cache working
  - [ ] Code-Server → PostgreSQL: config loading
  - [ ] Prometheus → Code-Server: metrics scraped
  - [ ] Jaeger → Code-Server: traces received

- [ ] **Docker Compose Status**
  - [ ] All 13 services showing "Up" or "healthy"
  - [ ] `docker-compose ps` shows all statuses green
  - [ ] No container restarts in last 5 minutes

**Sign-off:** _______________________ Date: ___________

---

## PHASE 4: Validation & Hardening (Week 4, Day 22-25)

### Security Validation

- [ ] **TLS/SSL Assessment**
  - [ ] SSL Labs grade: A+ (https://www.ssllabs.com/)
  - [ ] TLS 1.3 enforced (no downgrade to 1.2)
  - [ ] HSTS configured (31536000 seconds)
  - [ ] OCSP stapling response valid
  - [ ] Certificate transparency logs checked

- [ ] **Application Security**
  - [ ] OWASP Top 10 assessment completed
  - [ ] XSS protection verified (CSP policy working)
  - [ ] CSRF tokens present and valid
  - [ ] SQL injection protection verified (parameterized queries)
  - [ ] No hardcoded credentials found:
    `docker-compose config | grep -iE "password|secret|token|apikey" | grep -v "\$\{" | wc -l` = 0

- [ ] **Container Security**
  - [ ] Image scan results reviewed: `trivy image <name>`
  - [ ] Base images from official registries
  - [ ] No running as root (all services use uid 1000+)
  - [ ] Read-only root filesystem enforced where possible

- [ ] **Network Security**
  - [ ] All inter-service communication encrypted (TLS inside Docker network)
  - [ ] External API calls use HTTPS only
  - [ ] Private keys not logged anywhere
  - [ ] Network policies enforced (if using IPAM)

### Performance Validation

- [ ] **Load Testing**
  - [ ] Run: `ab -n 10000 -c 100 https://ide.kushnir.cloud/health`
  - [ ] p50 latency: < 100ms ✓
  - [ ] p95 latency: < 200ms ✓
  - [ ] p99 latency: < 500ms ✓
  - [ ] Error rate: < 0.1% ✓
  - [ ] Throughput: > 100 req/sec ✓

- [ ] **Endurance Test**
  - [ ] Run vegeta for 30 minutes at 50 req/sec
  - [ ] No memory leaks (check: `watch docker stats`)
  - [ ] Connection count stable
  - [ ] CPU usage stable (no runaway processes)
  - [ ] Disk space not growing excessively

- [ ] **Database Performance**
  - [ ] PostgreSQL query latency: p95 < 100ms
  - [ ] Redis latency: p95 < 5ms
  - [ ] Connection pool size optimized
  - [ ] No slow queries in logs

### Observability Validation

- [ ] **Metrics Collection**
  - [ ] Prometheus: 10/10 scrape jobs healthy
  - [ ] Series count < 1M (manageable)
  - [ ] No scrape errors
  - [ ] Retention working (data older than 365d deleted)

- [ ] **Log Collection**
  - [ ] All services sending logs to Elasticsearch
  - [ ] Log volume reasonable (< 1GB/day)
  - [ ] Log fields indexed correctly
  - [ ] Kibana dashboards showing real data

- [ ] **Tracing**
  - [ ] Jaeger receiving spans from Code-Server
  - [ ] Trace IDs correlate with logs
  - [ ] Sampling working (only ~20% of requests traced)
  - [ ] Span context propagated correctly

- [ ] **Alerting**
  - [ ] Test alert fires correctly
  - [ ] Alert routes to Slack channel
  - [ ] Alert routes to PagerDuty on-call
  - [ ] Alert deduplication working
  - [ ] Silences honored (no duplicate notifications)

### Disaster Recovery Validation

- [ ] **Backup Verification**
  - [ ] PostgreSQL backup created and verified restorable
  - [ ] Redis persistence (AOF + RDB) working
  - [ ] Elasticsearch snapshots working
  - [ ] Off-site backup (S3/GCS) replicating
  - [ ] Retention policy enforced (30-day rolling window)

- [ ] **Failover Testing**
  - [ ] Kill PostgreSQL container, service recovers (restart policy)
  - [ ] Kill Redis container, service recovers
  - [ ] Kill Code-Server container, service recovers
  - [ ] Kill Caddy container, service recovers (and requests queue)
  - [ ] All recovery times < 1 minute

- [ ] **Restore Procedure**
  - [ ] Documented restore from backup steps
  - [ ] Test restore to warm standby (successful)
  - [ ] RTO validation: < 15 minutes
  - [ ] RPO validation: < 5 minutes of data loss

### Compliance Validation

- [ ] **Audit Trail**
  - [ ] All user actions logged (in PostgreSQL audit schema)
  - [ ] Logs immutable (write-once to storage)
  - [ ] Logs encrypted at rest
  - [ ] Admin actions tracked separately

- [ ] **Data Protection**
  - [ ] Sensitive data at rest: encrypted (database TDE)
  - [ ] Sensitive data in transit: TLS 1.3
  - [ ] PII fields identified and masked in logs
  - [ ] Database encryption key rotated quarterly

- [ ] **Access Control**
  - [ ] RBAC enforced: admin, user, viewer, guest roles
  - [ ] MFA required for admin access
  - [ ] Service-to-service auth via Vault AppRole
  - [ ] No shared credentials

**Sign-off:** _______________________ Date: ___________

---

## PHASE 5: Production Go-Live (Day 26+)

### Pre-Go-Live Checklist

- [ ] All phases signed off by respective owners
- [ ] Incident response plan reviewed by team
- [ ] On-call escalation documented
- [ ] Runbook for common issues prepared
- [ ] Rollback procedure tested
- [ ] Communication plan for outages established

### Go-Live Execution

- [ ] **Notification**
  - [ ] Status page updated (maintenance window scheduled)
  - [ ] Team notified in Slack
  - [ ] Stakeholders informed

- [ ] **Final Verification**
  - [ ] Run pre-flight checklist: `./scripts/production-preflight.sh`
  - [ ] All checks passing (100%)
  - [ ] No recent error in application logs (last 1 hour)
  - [ ] Resource utilization normal

- [ ] **Traffic Activation**
  - [ ] DNS cut-over to production (if from staging)
  - [ ] CloudFlare CDN cache purged
  - [ ] Monitor error rate (watch for spike)
  - [ ] Monitor latency (watch p99)
  - [ ] Check PagerDuty for alerts

- [ ] **Post-Go-Live Monitoring (First 24 hours)**
  - [ ] Continuously monitor error rate (should stay < 0.1%)
  - [ ] Monitor latency (p95 < 200ms)
  - [ ] Check disk usage growth rate (should be stable)
  - [ ] Review database slow query log (any new slow queries?)
  - [ ] Team on high alert for issues

### Ongoing SLA Targets

- [ ] **Availability:** 99.99% (4 nines) = max 4.3 minutes downtime/month
- [ ] **Response Time:** p95 < 200ms, p99 < 500ms
- [ ] **Error Rate:** < 0.1% (< 1000 errors per 1M requests)
- [ ] **MTTD:** < 1 minute (mean time to detect)
- [ ] **MTTR:** < 5 minutes for P0 incidents

**Sign-off (Go-Live Authority):** _______________________ Date: ___________

---

## Sign-Off Summary

| Phase | Owner | Status | Date | Sign-Off |
|-------|-------|--------|------|----------|
| Phase 1: Pre-Deployment | DevOps Lead | [ ] Ready | _____ | __________ |
| Phase 2: Security Setup | Security Eng | [ ] Ready | _____ | __________ |
| Phase 3: Deployment | DevOps Lead | [ ] Ready | _____ | __________ |
| Phase 4: Validation | QA/SRE | [ ] Ready | _____ | __________ |
| Phase 5: Go-Live | CTO/Director | [ ] Ready | _____ | __________ |

---

**Next Review Date:** ___________  
**Incident Review:** (post-launch, after 1 week)  
**Full Audit:** (quarterly)  

