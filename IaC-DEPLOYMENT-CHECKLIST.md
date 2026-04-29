# INFRASTRUCTURE AS CODE - PRODUCTION DEPLOYMENT CHECKLIST

**Date:** April 29, 2026  
**Status:** Ready for Production Deployment  
**Environment:** 2-node HA cluster (PRIMARY + REPLICA)  

---

## PRE-DEPLOYMENT CHECKLIST

- [ ] **Verify connectivity to both nodes**
  ```bash
  ssh akushnir@192.168.168.31 "echo PRIMARY ready"
  ssh akushnir@192.168.168.42 "echo REPLICA ready"
  ```

- [ ] **Verify Ansible installed**
  ```bash
  ansible --version
  ```

- [ ] **Review ansible/inventory.yml**
  ```bash
  cat ansible/inventory.yml
  ```

- [ ] **Review docker-compose.yml**
  ```bash
  cat docker-compose.production-replica.yml | head -50
  ```

- [ ] **Git status clean**
  ```bash
  git status
  ```

---

## STEP 1: DEPLOY INFRASTRUCTURE & SERVICES

### Option A: Automated (Recommended)
```bash
bash scripts/ops/iac-deploy.sh
```

**Time:** ~15 minutes  
**Handles:** Everything automatically  
**Result:** Production-ready cluster with monitoring  

### Option B: Manual Steps
```bash
# Deploy cluster infrastructure and services
ansible-playbook \
  -i ansible/inventory.yml \
  ansible/deploy-cluster.yml \
  -v

# Expected output:
# ✅ Step 1: Infrastructure created
# ✅ Step 2: Services deployed (18 per node)
# ✅ Step 3: Database replication configured
# ✅ Step 4: Service consistency verified
# ✅ Step 5: Health checks passed
```

---

## STEP 2: VERIFY DEPLOYMENT

### 2a. Check Services on PRIMARY
```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && docker-compose ps"
```

**Expected:**
```
NAME                                    STATUS
code-server-enterprise-postgres         Up
code-server-enterprise-redis            Up
code-server-enterprise-mongodb          Up
code-server-enterprise-elasticsearch    Up
code-server-enterprise-qdrant           Up
code-server-enterprise-prometheus       Up
code-server-enterprise-grafana          Up
code-server-enterprise-loki             Up
code-server-enterprise-tempo            Up
code-server-enterprise-alertmanager     Up
code-server-enterprise-caddy            Up
code-server-enterprise-api-service      Up
code-server-enterprise-web-service      Up
code-server-enterprise-user-service     Up
code-server-enterprise-data-service     Up
code-server-enterprise-analytics-service Up
code-server-enterprise-pgadmin          Up
code-server-enterprise-redis-commander  Up

18 total services
```

### 2b. Check Services on REPLICA
```bash
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && docker-compose ps"
```

**Expected:** Identical to PRIMARY (18 services)

### 2c. Compare Both Nodes
```bash
# Get service list from PRIMARY
SERVICES_PRIMARY=$(ssh akushnir@192.168.168.31 \
  "cd ~/code-server-enterprise-ops && docker-compose ps --services | sort")

# Get service list from REPLICA
SERVICES_REPLICA=$(ssh akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise-ops && docker-compose ps --services | sort")

# Compare (should be identical)
diff <(echo "$SERVICES_PRIMARY") <(echo "$SERVICES_REPLICA")
```

**Expected:** No output (lists are identical) ✅

---

## STEP 3: VERIFY DATABASE REPLICATION

### 3a. Check Replication Status
```bash
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-postgres psql -U postgres -d app_db -c \
  "SELECT client_addr, state, write_lag FROM pg_stat_replication;"
EOF
```

**Expected:**
```
  client_addr   |   state   | write_lag
----------------+-----------+----------
192.168.168.42  | streaming | 00:00:00.3
```

**Interpretation:**
- `client_addr: 192.168.168.42` = REPLICA connected
- `state: streaming` = Replication active
- `write_lag: 0.3s` = Lag is 300ms (target: <1s) ✅

### 3b. Verify Replication User
```bash
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-postgres psql -U postgres -c \
  "SELECT usename, usesuper, usecreatedb FROM pg_user WHERE usename = 'replication_user';"
EOF
```

**Expected:**
```
  usename      | usesuper | usecreatedb
---------------+----------+----------
replication_user|    f    |    f
```

### 3c. Check WAL Archiving
```bash
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-postgres psql -U postgres -c \
  "SHOW wal_level; SHOW archive_mode; SHOW archive_command;"
EOF
```

**Expected:**
```
 wal_level    | replica
 archive_mode | on
```

---

## STEP 4: TEST SERVICE CONNECTIVITY

### 4a. Test API Gateway
```bash
# PRIMARY
curl -v http://192.168.168.31/health
# Expected: 200 OK

# REPLICA
curl -v http://192.168.168.42/health
# Expected: 200 OK
```

### 4b. Test PostgreSQL
```bash
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-postgres psql -U postgres -c "SELECT version();"
EOF
```

**Expected:** PostgreSQL version 16.x output

### 4c. Test Redis
```bash
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-redis redis-cli PING
EOF
```

**Expected:** `PONG` ✅

### 4d. Test MongoDB
```bash
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-mongodb mongosh -u admin -p password --authenticationDatabase admin --eval "db.adminCommand('ping')"
EOF
```

**Expected:** `{ ok: 1 }` ✅

---

## STEP 5: CONFIGURE OBSERVABILITY

### 5a. Deploy Monitoring Stack
```bash
ansible-playbook \
  -i ansible/inventory.yml \
  ansible/observability.yml \
  -v

# Expected output:
# ✅ Step 1: Grafana ready
# ✅ Step 2: Datasources added (Prometheus, Loki, Tempo)
# ✅ Step 3: 4 dashboards created
# ✅ Step 4: 10 alert rules configured
# ✅ Step 5: AlertManager channels configured
# ✅ Step 6: Verification complete
```

### 5b. Access Grafana
```
URL: http://192.168.168.31:3000
Username: admin
Password: admin
```

**Verify:**
- [ ] 4 Dashboards visible (Infrastructure, Services, Database, Business)
- [ ] All datasources connected (Prometheus, Loki, Tempo)
- [ ] 10 Alert rules loaded

### 5c. Access Prometheus
```
URL: http://192.168.168.31:9090
```

**Verify:**
- [ ] All targets scraped (25+ targets)
- [ ] No "RED" or "DOWN" states
- [ ] Metrics collecting

### 5d. Access AlertManager
```
URL: http://192.168.168.31:9093
```

**Verify:**
- [ ] Alert routing rules configured
- [ ] Notification channels available

---

## STEP 6: CONFIGURE ALERT CHANNELS

### 6a. Slack Integration
1. **Create Slack App**
   - Go to https://api.slack.com/apps
   - Create new app
   - Enable "Incoming Webhooks"
   - Create webhook for #critical-alerts channel

2. **Update ansible/inventory.yml**
   ```yaml
   alertmanager:
     slack_webhook_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
     slack_channel: "#critical-alerts"
   ```

3. **Re-run observability playbook**
   ```bash
   ansible-playbook \
     -i ansible/inventory.yml \
     ansible/observability.yml
   ```

### 6b. PagerDuty Integration (Optional)
1. **Create PagerDuty Service**
   - Go to PagerDuty dashboard
   - Create new service
   - Generate integration key

2. **Update ansible/inventory.yml**
   ```yaml
   alertmanager:
     pagerduty_service_key: "YOUR_SERVICE_KEY"
   ```

3. **Re-run observability playbook**
   ```bash
   ansible-playbook \
     -i ansible/inventory.yml \
     ansible/observability.yml
   ```

---

## STEP 7: HEALTH CHECK AUTOMATION

### 7a. Create Daily Health Check Script
```bash
cat > scripts/ops/daily-health-check.sh << 'EOF'
#!/bin/bash
set -e

echo "🏥 CLUSTER HEALTH CHECK"
echo "======================="
echo ""

# Check PRIMARY
echo "PRIMARY (192.168.168.31):"
ssh akushnir@192.168.168.31 "docker-compose ps -q | wc -l" | xargs echo "  Services:"

# Check REPLICA
echo "REPLICA (192.168.168.42):"
ssh akushnir@192.168.168.42 "docker-compose ps -q | wc -l" | xargs echo "  Services:"

# Check replication lag
echo "Replication Lag:"
ssh akushnir@192.168.168.31 << 'REPL_CHECK'
docker exec code-server-enterprise-postgres psql -U postgres -d app_db -c \
  "SELECT write_lag FROM pg_stat_replication LIMIT 1;" | tail -1
REPL_CHECK

echo "✅ Health check complete"
EOF

chmod +x scripts/ops/daily-health-check.sh
```

### 7b. Schedule Daily Health Checks
```bash
# Add to crontab
crontab -e

# Add this line (run at 8 AM daily)
0 8 * * * /home/akushnir/code-server/scripts/ops/daily-health-check.sh
```

---

## STEP 8: BACKUP CONFIGURATION

### 8a. Automated Daily Backups
```bash
# Create backup script
mkdir -p scripts/ops/backups

cat > scripts/ops/backup-database.sh << 'EOF'
#!/bin/bash
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/akushnir/code-server-enterprise-ops/backups"

# Backup PostgreSQL from PRIMARY
ssh akushnir@192.168.168.31 << BACKUP_CMD
docker exec code-server-enterprise-postgres pg_dump \
  -U postgres app_db > ${BACKUP_DIR}/app_db_${BACKUP_DATE}.sql
BACKUP_CMD

echo "✅ Backup created: app_db_${BACKUP_DATE}.sql"
EOF

chmod +x scripts/ops/backup-database.sh
```

### 8b. Schedule Backups
```bash
# Add to crontab (run at 2 AM daily)
0 2 * * * /home/akushnir/code-server/scripts/ops/backup-database.sh
```

---

## STEP 9: PRODUCTION VALIDATION

### 9a. Load Testing
```bash
# Simple load test (10 requests per second for 5 minutes)
ab -n 3000 -c 10 http://192.168.168.31/health
```

### 9b. Failover Testing
```bash
# Simulate PRIMARY failure
# 1. Note PostgreSQL lag on REPLICA
# 2. Verify monitoring alerts trigger
# 3. Promote REPLICA to PRIMARY
ssh akushnir@192.168.168.42 << 'EOF'
docker exec code-server-enterprise-postgres pg_ctl promote
EOF
```

### 9c. Replication Recovery
```bash
# After failover testing, reinitialize replication
ansible-playbook \
  -i ansible/inventory.yml \
  ansible/deploy-cluster.yml \
  --tags replication
```

---

## STEP 10: DOCUMENTATION & HANDOFF

### 10a. Generate Deployment Report
```bash
mkdir -p reports

cat > reports/deployment-${DATE}.md << 'EOF'
# Production Deployment Report
- Date: $(date)
- Environment: 2-node HA cluster
- PRIMARY: 192.168.168.31
- REPLICA: 192.168.168.42
- Services: 18 per node (36 total)
- Database Replication: <1s lag
- Observability: 4 dashboards, 10 alerts
- Status: ✅ PRODUCTION READY
EOF

git add reports/
git commit -m "doc: Production deployment report"
```

### 10b. Create Operations Runbook
```bash
cat > OPERATIONS_RUNBOOK.md << 'EOF'
# Production Operations Runbook

## Daily Tasks
- [ ] Review Grafana dashboards (8 AM)
- [ ] Check replication lag (hourly)
- [ ] Verify backup completion (8:30 AM)

## Weekly Tasks
- [ ] Review alert logs
- [ ] Test failover scenario
- [ ] Database VACUUM maintenance

## Monthly Tasks
- [ ] Full cluster failover test
- [ ] Capacity planning review
- [ ] Security audit

## Emergency Procedures
- [ ] Service restart guide
- [ ] Database failover guide
- [ ] Network troubleshooting guide

EOF

git add OPERATIONS_RUNBOOK.md
git commit -m "doc: Operations runbook for production cluster"
```

---

## TROUBLESHOOTING

### Services Not Starting
```bash
# Check logs
ssh akushnir@192.168.168.31 "docker-compose logs SERVICE_NAME"

# Restart service
ssh akushnir@192.168.168.31 "docker-compose restart SERVICE_NAME"

# Re-run full deployment (safe, idempotent)
ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
```

### High Replication Lag
```bash
# Check network latency
ping -c 10 192.168.168.42

# Check PRIMARY load
ssh akushnir@192.168.168.31 "docker stats --no-stream code-server-enterprise-postgres"

# Check REPLICA I/O
ssh akushnir@192.168.168.42 "iostat -x 1 5"
```

### Grafana Dashboard Empty
```bash
# Verify Prometheus scraping
curl http://192.168.168.31:9090/api/v1/query?query=up

# Force metric scrape
ssh akushnir@192.168.168.31 "docker exec code-server-enterprise-prometheus kill -HUP 1"

# Wait 30 seconds and refresh Grafana
```

---

## SIGN-OFF CHECKLIST

- [ ] All 18 services running on PRIMARY
- [ ] All 18 services running on REPLICA
- [ ] Service lists are identical
- [ ] Database replication active (<1s lag)
- [ ] API Gateway responding on both nodes
- [ ] Grafana dashboards displaying data
- [ ] 10 alert rules loaded
- [ ] Alert channels configured (Slack/PagerDuty)
- [ ] Daily backups scheduled
- [ ] Health checks automated
- [ ] Operations runbook created
- [ ] All infrastructure in git
- [ ] Deployment reproducible from IaC
- [ ] Production ready ✅

---

**Status:** ✅ **READY FOR PRODUCTION DEPLOYMENT**

**Next Action:** Run `bash scripts/ops/iac-deploy.sh` to deploy everything automatically.
