# LOCAL DEPLOYMENT CHECKLIST
## Single-Host Production Deployment (192.168.168.31)

**Version:** 1.0 - Local Focus  
**Status:** ACTIVE  
**Target:** 192.168.168.31 (single host, no cloud dependencies)  
**Timeline:** 4 weeks

---

## PHASE 1: Pre-Deployment (Week 1, Day 1-5)

### Host Verification

- [ ] **SSH Access**
  - [ ] Can SSH to 192.168.168.31 without password (key-based auth)
  - [ ] User has sudo access
  - [ ] Jump host/bastion configured (if needed)

- [ ] **Hardware Check**
  - [ ] CPU cores: `nproc` shows 8 or more
  - [ ] RAM: `free -h` shows 32GB or more
  - [ ] Disk space: `df -h /` shows 500GB+ free
  - [ ] SSD storage (not magnetic): `lsblk -d -D` check DISC-GRAN
  - [ ] No resource constraints on VM

- [ ] **Software Installed**
  - [ ] Linux kernel 5.10+: `uname -r`
  - [ ] Docker 20.10+: `docker --version`
  - [ ] Docker Compose 2.10+: `docker-compose --version`
  - [ ] Git installed: `git --version`
  - [ ] Curl installed: `curl --version`
  - [ ] jq installed: `jq --version`

- [ ] **Docker Configuration**
  - [ ] Docker daemon running: `sudo systemctl status docker`
  - [ ] User can run docker: `docker ps` (no permission errors)
  - [ ] Docker bridge network available: `docker network ls`
  - [ ] Docker volumes working: `docker volume create test && docker volume rm test`

### Storage Setup

- [ ] **Persistent Data Directory**
  - [ ] `/data` directory created: `mkdir -p /data`
  - [ ] Subdirectories created:
    - [ ] `/data/postgres`
    - [ ] `/data/redis`
    - [ ] `/data/ollama`
    - [ ] `/data/prometheus`
    - [ ] `/data/elasticsearch`
    - [ ] `/data/caddy`
    - [ ] `/data/vault`
  - [ ] Owner set to 1000:1000: `chown -R 1000:1000 /data`
  - [ ] Permissions: `chmod -R 755 /data`
  - [ ] Disk space sufficient: `df -h /data` shows < 80% used

- [ ] **Backup Directory** (local backups)
  - [ ] `/backups` directory created: `mkdir -p /backups`
  - [ ] Sufficient space: `df -h /backups` shows 200GB+ available
  - [ ] Owner set: `chown -R 1000:1000 /backups`

### Network Setup

- [ ] **Local DNS Resolution**
  - [ ] Edit `/etc/hosts`
  - [ ] Add: `127.0.0.1 workspace.local`
  - [ ] Add: `192.168.168.31 workspace.local`
  - [ ] Verify: `ping workspace.local` (should resolve)

- [ ] **Docker Network**
  - [ ] Create bridge network: `docker network create production-enterprise`
  - [ ] Verify: `docker network ls | grep production`
  - [ ] Subnet correct: `docker network inspect production-enterprise | jq '.IPAM.Config[0].Subnet'`

- [ ] **Firewall (if applicable)**
  - [ ] Port 80 open: `sudo iptables -L | grep 80` (or firewall rules)
  - [ ] Port 443 open: `sudo iptables -L | grep 443`
  - [ ] Port 22 (SSH) open for access
  - [ ] No restrictions to localhost

### Files & Repository

- [ ] **Code Repository**
  - [ ] Code cloned: `git clone ... code-server-enterprise`
  - [ ] Latest version: `git log -1 --oneline`
  - [ ] No local changes: `git status` (clean)
  - [ ] All config files present:
    - [ ] `docker-compose.production.yml`
    - [ ] `Caddyfile.production`
    - [ ] `.env.production`
    - [ ] `prometheus-production.yml`
    - [ ] `alertmanager-production.yml`
    - [ ] `postgres-init.sql`

- [ ] **Configuration Files Ready**
  - [ ] Environment template reviewed: `.env.production`
  - [ ] Caddyfile reviewed: `Caddyfile.production`
  - [ ] Docker Compose reviewed: `docker-compose.production.yml`
  - [ ] No hardcoded secrets: `grep -r "password" . | grep -v "{{" | grep -v "${"` (should be empty)

### Team & Access

- [ ] **Personnel**
  - [ ] DevOps lead identified
  - [ ] On-call engineer assigned
  - [ ] Database administrator assigned
  - [ ] Security reviewer assigned

- [ ] **Credentials**
  - [ ] SSH keys copied to secure location
  - [ ] GitHub token available (for pulling private repos)
  - [ ] OAuth credentials ready (Google/Azure/etc)
  - [ ] All in password manager (not committed to git)

**Sign-off:** _______________________ Date: ___________

---

## PHASE 2: Credentials & Security (Week 2, Day 8-14)

### Vault Deployment (Local)

- [ ] **Vault Docker Image**
  - [ ] Image available: `docker images | grep vault`
  - [ ] Latest version: `docker inspect vault | jq '.RepoTags'`
  - [ ] Size reasonable (< 200MB)

- [ ] **Vault Container Started**
  - [ ] Container running: `docker-compose up -d vault`
  - [ ] Status healthy: `docker-compose ps vault`
  - [ ] API accessible: `curl http://localhost:8200/v1/sys/health`

- [ ] **Vault Initialization**
  - [ ] Initialized: `docker-compose exec vault vault operator init -key-shares=5 -key-threshold=3`
  - [ ] Got 5 unseal keys (distributed securely)
  - [ ] Got 1 initial root token (stored securely)
  - [ ] Keys stored in secure location (password manager, not git)

- [ ] **Vault Unsealing**
  - [ ] Vault status: `docker-compose exec vault vault status`
  - [ ] Sealed status: false (unsealed)
  - [ ] Auth enabled: true
  - [ ] Used 3 of 5 keys to unseal

- [ ] **Vault Configuration**
  - [ ] Audit logging enabled: `docker-compose exec vault vault audit list`
  - [ ] Secret engine enabled: `docker-compose exec vault vault secrets list` (should see 'secret/')
  - [ ] Path configured correctly: 'secret/' should be KV v2

### Load Secrets (No Cloud Dependencies)

- [ ] **OAuth Credentials**
  - [ ] Google OAuth: `vault kv put secret/production/google/oauth client-id='...' client-secret='...'`
  - [ ] OR Azure OAuth: stored in Vault
  - [ ] Verified readable: `vault kv get secret/production/google/oauth` (shows values)

- [ ] **Database Credentials**
  - [ ] PostgreSQL password: `vault kv put secret/production/postgres password='<strong-password>'`
  - [ ] Redis password: `vault kv put secret/production/redis password='<strong-password>'`
  - [ ] Elasticsearch password: `vault kv put secret/production/elasticsearch password='<strong-password>'`
  - [ ] All verified readable

- [ ] **Application Secrets**
  - [ ] Code-Server password: stored in Vault
  - [ ] SSH private key: stored in Vault (if needed)
  - [ ] GitHub token: stored in Vault (if using private repos)

- [ ] **Alerting & Monitoring**
  - [ ] Slack webhook URL: `vault kv put secret/production/slack webhook_url='...'`
  - [ ] Email SMTP credentials: stored in Vault
  - [ ] PagerDuty (if using): integration key stored

- [ ] **TLS Certificates**
  - [ ] Self-signed certificate generated OR
  - [ ] Local CA certificate created
  - [ ] Certificate path accessible by Caddy
  - [ ] Private key not world-readable

### Environment Setup

- [ ] **.env File Created**
  - [ ] Copied from template: `cp .env.production .env`
  - [ ] All `${VAULT_*}` variables present
  - [ ] No hardcoded passwords: `grep "password\|secret" .env | grep -v "${"` (empty)
  - [ ] Permissions: `chmod 600 .env`
  - [ ] Verified not committed to git: check `.gitignore`

- [ ] **Local DNS for TLS**
  - [ ] Certificate includes DN: `workspace.local` (in SANs)
  - [ ] Or using self-signed with browser warning (acceptable for local)
  - [ ] Caddy configured for `workspace.local` domain
  - [ ] ACME skipped (no CloudFlare for local)

### Security Validation

- [ ] **No Hardcoded Secrets**
  - [ ] Docker Compose config check: `docker-compose config | grep -iE "password|secret|token"` (no matches outside ${})
  - [ ] Dockerfile verification: `grep -r "password\|secret" ./Dockerfile*` (none found)
  - [ ] .env verification: Only `${VAULT_*}` references
  - [ ] All credentials from environment only

- [ ] **Vault Security**
  - [ ] Root token revoked (after initial setup)
  - [ ] Unseal keys stored securely (split across team members)
  - [ ] Vault audit logs flowing: `docker-compose logs vault | grep -i audit`
  - [ ] Only authorized services can read secrets

**Sign-off:** _______________________ Date: ___________

---

## PHASE 3: Application Deployment (Week 3, Day 15-21)

### Data Layer (PostgreSQL + Redis)

- [ ] **PostgreSQL**
  - [ ] Container started: `docker-compose up -d postgres`
  - [ ] Healthy: `docker-compose ps postgres` (Up + healthy)
  - [ ] Responsive: `docker-compose exec postgres pg_isready` (accepting connections)
  - [ ] User created: `docker-compose exec postgres psql -c "\du" | grep ide_app`
  - [ ] Database initialized: `docker-compose exec postgres psql -c "\l" | grep workspace`
  - [ ] Data persists: `ls /data/postgres/ | grep -E "base|pg_wal"` (has data)

- [ ] **PostgreSQL Initialization**
  - [ ] postgres-init.sql applied: `docker-compose exec postgres psql -f postgres-init.sql`
  - [ ] Audit schema created: `docker-compose exec postgres psql -c "\dn" | grep audit`
  - [ ] Sessions schema created: `docker-compose exec postgres psql -c "\dn" | grep sessions`
  - [ ] RBAC configured: `docker-compose exec postgres psql -c "SELECT * FROM rbac.roles" | wc -l` (4 roles)
  - [ ] All permissions set: `docker-compose exec postgres psql -c "SELECT * FROM rbac.permissions" | wc -l` (6+)

- [ ] **Redis**
  - [ ] Container started: `docker-compose up -d redis`
  - [ ] Healthy: `docker-compose ps redis` (Up + healthy)
  - [ ] Responsive: `docker-compose exec redis redis-cli ping` (PONG)
  - [ ] Persistence enabled: `docker-compose exec redis redis-cli CONFIG GET save` (has value)
  - [ ] Data persists: `ls /data/redis/ | grep -E "rdb|aof"` (has backup files)

### Security & Auth Layer

- [ ] **Vault (Already started in Phase 2)**
  - [ ] Running: `docker-compose ps vault` (healthy)
  - [ ] Secrets accessible: `docker-compose exec vault vault secrets list` (secret/ visible)

- [ ] **OAuth2-Proxy**
  - [ ] Container started: `docker-compose up -d oauth2-proxy`
  - [ ] Healthy: `docker-compose ps oauth2-proxy` (healthy)
  - [ ] Responsive: `docker-compose exec oauth2-proxy curl -s http://localhost:4180/ping | grep OK`
  - [ ] OAuth config loaded: `docker-compose logs oauth2-proxy 2>&1 | grep -i "client\|oauth"` (no errors)

### Observability Stack

- [ ] **Prometheus**
  - [ ] Container started: `docker-compose up -d prometheus`
  - [ ] Healthy: `docker-compose ps prometheus`
  - [ ] Web UI: `curl -s http://localhost:9090/ | grep Prometheus` (working)
  - [ ] All targets configured: `curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'` (10+)
  - [ ] Data flowing: `curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'` (>0)

- [ ] **Elasticsearch**
  - [ ] Container started: `docker-compose up -d elasticsearch`
  - [ ] Healthy: `docker-compose ps elasticsearch`
  - [ ] Cluster healthy: `curl -s http://localhost:9200/_cluster/health | jq '.status'` (green/yellow)
  - [ ] Indices created: `curl -s http://localhost:9200/_cat/indices | wc -l` (>0 indices)

- [ ] **Kibana**
  - [ ] Container started: `docker-compose up -d kibana`
  - [ ] Healthy: `docker-compose ps kibana`
  - [ ] Web UI accessible: `curl -s http://localhost:5601/api/status | jq '.state'` (green)
  - [ ] Datasource connected: see logs for no "Elasticsearch not available"

- [ ] **Jaeger**
  - [ ] Container started: `docker-compose up -d jaeger`
  - [ ] Healthy: `docker-compose ps jaeger`
  - [ ] Collector working: `curl -s http://localhost:14268/api/traces >/dev/null && echo OK`

- [ ] **AlertManager**
  - [ ] Container started: `docker-compose up -d alertmanager`
  - [ ] Healthy: `docker-compose ps alertmanager`
  - [ ] Config valid: `docker-compose logs alertmanager 2>&1 | grep -i "error\|failed"` (no errors)
  - [ ] Routes configured: Check `alertmanager-production.yml` has slack/email receivers

### Application Services

- [ ] **Caddy Reverse Proxy**
  - [ ] Container started: `docker-compose up -d caddy`
  - [ ] Healthy: `docker-compose ps caddy`
  - [ ] Listening on 80/443: `ss -tlnp | grep caddy`
  - [ ] TLS working: `openssl s_client -connect localhost:443` (no errors)
  - [ ] Routes configured: `docker-compose logs caddy 2>&1 | grep -i "route\|listen"`

- [ ] **Code-Server**
  - [ ] Container started: `docker-compose up -d code-server`
  - [ ] Healthy: `docker-compose ps code-server`
  - [ ] Web interface: `curl -s http://localhost:7680/ | grep code-server` (returns HTML)
  - [ ] OAuth redirect: Login attempts redirect to OAuth

- [ ] **Ollama**
  - [ ] Container started: `docker-compose up -d ollama`
  - [ ] Healthy: `docker-compose ps ollama`
  - [ ] Model available: `docker-compose exec ollama ollama list` (shows installed models)
  - [ ] API working: `curl -s http://localhost:11434/api/tags | jq '.models | length'` (>0)

- [ ] **Monitoring Agents**
  - [ ] Node-Exporter running: `docker-compose ps node-exporter` (healthy)
  - [ ] cAdvisor running: `docker-compose ps cadvisor` (healthy)
  - [ ] Metrics flowing: `curl -s http://localhost:9100/metrics | wc -l` (>100 lines)

### Service Connectivity

- [ ] **All Services Interacting**
  - [ ] Code-Server → PostgreSQL: Check app config loads
  - [ ] Code-Server → Redis: Session cache working
  - [ ] OAuth2-Proxy → Vault: Secrets loading
  - [ ] Prometheus → All targets: All 10 scrape jobs active
  - [ ] Jaeger → Code-Server: Spans being collected

### Full Stack Status

- [ ] **All 13 Services Healthy**
  - [ ] `docker-compose ps` shows all 13 with "Up" or "healthy"
  - [ ] `docker-compose ps | grep -v "Up\|healthy"` (returns nothing)
  - [ ] No restarts in last 5 minutes: `docker-compose ps 2>&1 | grep -i "restarting"` (none)

**Sign-off:** _______________________ Date: ___________

---

## PHASE 4: Validation & Hardening (Week 4, Day 22-25)

### Security Audit (Local)

- [ ] **No Hardcoded Credentials**
  - [ ] Docker config clean: `docker-compose config 2>/dev/null | grep -iE "password|secret|token" | grep -v "\${" | wc -l` = 0
  - [ ] Image scan clean: `trivy image code-server-patched 2>&1 | grep "CRITICAL\|HIGH" | wc -l` = 0 or mitigated
  - [ ] Git history clean: `git log -S "password" --all` (no commits with hardcoded passwords)

- [ ] **TLS Configuration**
  - [ ] Certificate valid: `openssl x509 -in /data/caddy/cert.pem -noout -text` (dates OK)
  - [ ] Private key secure: `stat /data/caddy/key.pem` (mode 600)
  - [ ] Caddy TLS enforced: Check `Caddyfile.production` for `tls internal` or cert path

- [ ] **Access Control**
  - [ ] Database users proper: `docker-compose exec postgres psql -c "\du"` (3 users: ide_app, ide_readonly, ide_audit)
  - [ ] Vault auth required: `curl -s http://localhost:8200/v1/sys/health` (requires token)
  - [ ] OAuth enforced on app: Accessing app redirects to OAuth login

### Performance Testing (Local)

- [ ] **Load Testing**
  - [ ] Install ab: `apt-get install apache2-utils`
  - [ ] Run: `ab -n 1000 -c 50 http://localhost/health`
  - [ ] Results: p99 latency < 500ms, error rate < 0.1%
  - [ ] No timeouts or connection errors

- [ ] **Sustained Load**
  - [ ] Run for 5 minutes: `ab -t 300 -c 50 http://localhost/health`
  - [ ] Memory stable: `docker stats --no-stream code-server` (no growth)
  - [ ] CPU reasonable: < 70% average
  - [ ] Disk not growing: `du -sh /data/*` (stable sizes)

- [ ] **Latency Metrics**
  - [ ] p50 latency: < 100ms
  - [ ] p95 latency: < 200ms
  - [ ] p99 latency: < 500ms
  - [ ] Check Prometheus: `curl 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,http_request_duration_seconds_bucket)' | jq`

### Backup & Restore Testing

- [ ] **PostgreSQL Backup**
  - [ ] Create backup: `docker-compose exec postgres pg_dump > /tmp/backup.sql`
  - [ ] Verify file: `file /tmp/backup.sql | grep -i "sql"` (should be text)
  - [ ] Size reasonable: `ls -lh /tmp/backup.sql` (larger than a few KB)
  - [ ] Contains data: `grep -i "insert\|create" /tmp/backup.sql | tail -5` (has INSERT statements)

- [ ] **Redis Persistence**
  - [ ] BGSAVE works: `docker-compose exec redis redis-cli BGSAVE` (OK)
  - [ ] RDB file created: `ls -lh /data/redis/*.rdb`
  - [ ] AOF file created: `ls -lh /data/redis/*.aof` (if configured)

- [ ] **Restore Validation**
  - [ ] Stop PostgreSQL: `docker-compose stop postgres`
  - [ ] Delete data: `rm -rf /data/postgres/base` (BAD DATA)
  - [ ] Restart: `docker-compose up -d postgres`
  - [ ] Restore: `docker-compose exec postgres psql < /tmp/backup.sql`
  - [ ] Verify: `docker-compose exec postgres psql -c "SELECT COUNT(*) FROM ..."`

- [ ] **RTO/RPO Targets**
  - [ ] Recovery Time Objective (RTO): < 15 minutes (from backup)
  - [ ] Recovery Point Objective (RPO): < 5 minutes of data loss
  - [ ] Tested and documented

### Local SLA Validation

- [ ] **Availability (99.9%)**
  - [ ] Downtime allowed: ~45 minutes/month
  - [ ] Auto-restart working: Kill a service, verify it restarts
  - [ ] Recovery time < 5 minutes

- [ ] **Performance (p99 < 500ms)**
  - [ ] Verified in load testing
  - [ ] Prometheus queries confirm
  - [ ] No sustained latency > 500ms

- [ ] **Error Rate (< 0.1%)**
  - [ ] Load test error rate: `ab -n 10000 -c 100` shows < 10 errors
  - [ ] Application logs clean: `docker-compose logs | grep -i "error\|exception" | wc -l` < 5

### Compliance Check (Local)

- [ ] **Audit Logging**
  - [ ] PostgreSQL audit table populated: `docker-compose exec postgres psql -c "SELECT COUNT(*) FROM audit.audit_log"`
  - [ ] Logs not writable by app: `stat /data/postgres/ | grep "Uid"` (owned by postgres user)
  - [ ] Audit logs 2-year retention policy documented

- [ ] **Data Protection**
  - [ ] Passwords in vault: `vault kv list secret/production` (shows secrets)
  - [ ] No secrets in logs: `docker-compose logs 2>&1 | grep -iE "password=|token="` (should be empty)
  - [ ] Encryption at rest: PostgreSQL data in /data/ is encrypted (or documented as future work)

**Sign-off:** _______________________ Date: ___________

---

## PHASE 5: Production Go-Live (Day 26)

### Pre-Live Verification

- [ ] **All Phases Completed & Signed**
  - [ ] Phase 1: ✅
  - [ ] Phase 2: ✅
  - [ ] Phase 3: ✅
  - [ ] Phase 4: ✅

- [ ] **Final Checks**
  - [ ] All 13 services healthy: `docker-compose ps | grep "healthy\|Up" | wc -l` = 13
  - [ ] No recent errors: `docker-compose logs --since 10m | grep -i "error" | wc -l` < 3
  - [ ] Disk space: `df -h /data | awk 'NR==2 {print $5}'` < 80%
  - [ ] Backup exists: `ls -lh /backups/latest`

- [ ] **Team Readiness**
  - [ ] On-call engineer available
  - [ ] Incident response runbook reviewed
  - [ ] Escalation procedures documented
  - [ ] Status page updated

### Go-Live

- [ ] **Notification**
  - [ ] Team informed (Slack message sent)
  - [ ] Stakeholders notified
  - [ ] Status page: "System online"

- [ ] **Traffic Activation** (local)
  - [ ] DNS points to 192.168.168.31
  - [ ] TLS cert trusted locally
  - [ ] Use http://workspace.local or https://workspace.local

- [ ] **Initial Monitoring** (first 30 minutes)
  - [ ] Error rate normal: `curl 'http://localhost:9090/api/v1/query?query=rate(errors_total[5m])'`
  - [ ] Latency normal: p99 < 500ms
  - [ ] Resource usage normal: `docker stats --no-stream`
  - [ ] No alerts firing: `curl -s http://localhost:9093/api/v1/alerts | jq '.data | length'`

**Sign-off (Go-Live Authority):** _______________________ Date: ___________

---

## Post-Go-Live Operations (Ongoing)

### Daily Checks
```bash
docker-compose ps  # All 13 healthy
df -h /data        # < 80% used
docker stats       # Normal resource usage
```

### Weekly Tasks
- Review error logs
- Check backup completion
- Test 1 service restart (automatic failover)

### Monthly Tasks
- Full backup validation
- Performance trending
- Capacity planning

### Quarterly Tasks
- Disaster recovery drill (full restore test)
- Security audit
- Compliance review

---

## Summary

**Timeline:** 4 weeks to single-host production  
**Services:** 13 containerized microservices  
**Target Host:** 192.168.168.31 (local only)  
**SLA:** 99.9% (3 nines) with auto-restart  
**Storage:** 500GB+ local /data volume  
**Security:** Vault-managed secrets, no hardcoded credentials  
**Observability:** Prometheus + Jaeger + ELK (local)  
**Backup:** Local snapshots, 5-min RPO, 15-min RTO  

✅ **READY FOR LOCAL DEPLOYMENT**

