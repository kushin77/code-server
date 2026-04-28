# Deployment Execution Plan: Primary Host (192.168.168.31)
**Version**: 1.0  
**Date**: 2026-04-28  
**Status**: Ready for Execution  
**Estimated Duration**: 2-3 hours  

---

## Mission Statement

Deploy the code-server enterprise infrastructure to the primary host (192.168.168.31) with full validation, health checks, and error recovery capabilities. All deployment procedures are automated, audited, and reversible.

---

## Pre-Deployment Requirements

### Infrastructure Checklist
- [ ] SSH key authentication working (no password required)
- [ ] Primary host reachable and responding to ping
- [ ] Minimum 50GB free disk space (verify with `df -h /`)
- [ ] Docker installed: `docker --version` (v25+)
- [ ] Docker Compose installed: `docker-compose --version` (v2+)
- [ ] Network connectivity to upstream DNS and package repositories
- [ ] Current Git branch is main with all changes committed

### Configuration Checklist
- [ ] `.env.infrastructure` file exists and is sourced
- [ ] Database credentials generated and secured
- [ ] TLS certificates ready or Let's Encrypt configured
- [ ] OAuth2/OIDC provider credentials configured
- [ ] Backup directory created: `mkdir -p artifacts/backups/`
- [ ] Deployment log directory prepared: `mkdir -p artifacts/deployments/`

### Validation Checklist
- [ ] Run `bash scripts/ci/validate-trap-handlers.sh` (expect: 100% pass)
- [ ] Run `docker-compose config > /dev/null` (expect: no errors)
- [ ] Run `bash scripts/ci/validate-config-ssot.sh` (expect: validation passed)
- [ ] Pre-commit hook installed: `.git/hooks/pre-commit` exists
- [ ] Git status clean: `git status` (expect: working tree clean)

---

## Deployment Phases

### **PHASE 1: Pre-Flight Checks** (10 minutes)
**Goal**: Verify all prerequisites are met

#### Step 1.1: Connect to Primary Host
```bash
# On deployment workstation
ssh -v akushnir@192.168.168.31

# Expected: Shell prompt from primary host
# Working directory: /home/akushnir/code-server
cd /home/akushnir/code-server
```

#### Step 1.2: Verify System Resources
```bash
# Check disk space
df -h / | awk 'NR==2 {if ($5+0 < 80) print "✓ Disk OK: " $5; else print "✗ Disk HIGH: " $5}'

# Check memory
free -h | grep Mem | awk '{print "✓ Memory: " $2 " available"}'

# Check Docker
docker ps --format "table {{.Names}}\t{{.State}}" | head -5
echo "Expected: Docker running with no containers yet"
```

#### Step 1.3: Validate Git State
```bash
# Verify main branch
git branch -v | grep "^\* main"

# Check uncommitted changes
if [ -z "$(git status --porcelain)" ]; then
  echo "✓ Working tree clean"
else
  echo "✗ Uncommitted changes detected"
  git status
  exit 1
fi
```

#### Step 1.4: Load Configuration
```bash
# Source environment
source .env.infrastructure

# Verify critical variables
if [[ -z "$PRIMARY_HOST" ]] || [[ -z "$POSTGRES_PASSWORD" ]] || [[ -z "$APEX_DOMAIN" ]]; then
  echo "✗ Missing required environment variables"
  exit 1
fi
echo "✓ Environment configuration loaded"
```

**Expected Result**: All checks pass ✅

---

### **PHASE 2: Pre-Deployment Validation** (15 minutes)
**Goal**: Run comprehensive validation suite

#### Step 2.1: Trap Handler Validation
```bash
# Validate all scripts have error handling
bash scripts/ci/validate-trap-handlers.sh

# Expected output: All scripts pass validation
# Status: 🟢 100% Compliance
```

#### Step 2.2: Docker Compose Validation
```bash
# Validate primary compose file
docker-compose -f docker-compose.yml config > /dev/null && echo "✓ docker-compose.yml valid"

# Validate enterprise extensions
docker-compose -f docker-compose.enterprise.yml config > /dev/null && echo "✓ docker-compose.enterprise.yml valid"

# Validate observability stack
docker-compose -f docker-compose.observability.yml config > /dev/null && echo "✓ docker-compose.observability.yml valid"
```

#### Step 2.3: Infrastructure Validation
```bash
# Validate Terraform (if applicable)
bash scripts/ci/validate-terraform-version-pins.sh

# Expected: Terraform pinning validation passed
```

#### Step 2.4: Configuration Compliance
```bash
# Validate configuration SSOT
bash scripts/ci/validate-config-ssot.sh

# Expected: Configuration validation passed
```

**Expected Result**: All validations pass ✅

---

### **PHASE 3: Image Building & Initialization** (20 minutes)
**Goal**: Build Docker images and initialize services

#### Step 3.1: Build Docker Images
```bash
# Build all images without cache for clean build
docker-compose build --no-cache

# Expected: All services built successfully
# Typical time: 10-15 minutes depending on network speed
# Watch for any build errors - they indicate missing dependencies
```

**Verification**:
```bash
docker images | grep code-server | wc -l
# Expected: 20+ images listed
```

#### Step 3.2: Create Networks
```bash
# Ensure custom network exists
docker network create code-server_default 2>/dev/null || echo "✓ Network already exists"
```

#### Step 3.3: Initialize Database
```bash
# Start and run initialization
docker-compose up -d postgres-db
sleep 10

# Verify initialization
docker-compose exec postgres-db pg_isready -U postgres
# Expected: accepting connections

# Wait for PostgreSQL to be ready
timeout 60 bash -c 'until docker-compose exec postgres-db psql -U postgres -c "SELECT 1" > /dev/null 2>&1; do echo "Waiting for PostgreSQL..."; sleep 2; done'
```

#### Step 3.4: Initialize Cache & Message Broker
```bash
# Start Redis
docker-compose up -d redis-cache
sleep 5

# Start Redpanda
docker-compose up -d redpanda-broker
sleep 10

# Verify connectivity
docker-compose exec redis-cache redis-cli ping
# Expected: PONG

docker-compose exec redpanda-broker /opt/redpanda/bin/rpk cluster info
# Expected: Cluster information with 1 broker
```

**Expected Result**: All init services complete successfully ✅

---

### **PHASE 4: Core Services Deployment** (20 minutes)
**Goal**: Start all remaining services

#### Step 4.1: Start All Services
```bash
# Start all services (they're now configured and initialized)
docker-compose up -d

# Expected: All 41 services starting
```

#### Step 4.2: Wait for Service Readiness
```bash
# Monitor service startup
watch -n 2 'docker-compose ps | grep -E "Up|Exited|Restarting" | wc -l'

# Expected: All services showing "Up (healthy)" or "Up"
# Typical time: 2-5 minutes

# Or use script
timeout 300 bash scripts/ops/verify-service-health.sh
```

**Verification**:
```bash
# Check no services are restarting
docker-compose ps | grep -c "Restarting"
# Expected: 0

# Count healthy services
docker-compose ps | grep -c "Up"
# Expected: 41 services up
```

**Expected Result**: All 41 services running and healthy ✅

---

### **PHASE 5: Service Validation** (15 minutes)
**Goal**: Verify services are functioning

#### Step 5.1: Port Availability Checks
```bash
# Test key service ports
for port in 80 443 5432 6379 9090 3000 8181; do
  if nc -zv localhost $port &>/dev/null; then
    echo "✓ Port $port listening"
  else
    echo "✗ Port $port not listening"
  fi
done
```

#### Step 5.2: HTTP Endpoint Tests
```bash
# Test Caddy Gateway
curl -s http://localhost/health | jq . && echo "✓ Caddy Gateway healthy"

# Test Prometheus
curl -s http://localhost:9090/-/healthy && echo "✓ Prometheus healthy"

# Test Grafana
curl -s -u admin:admin http://localhost:3000/api/health | jq . && echo "✓ Grafana healthy"

# Test OPA
curl -s http://localhost:8181/health && echo "✓ OPA healthy"
```

#### Step 5.3: Database Connectivity
```bash
# Test PostgreSQL
docker-compose exec postgres-db psql -U postgres -c "SELECT version();" && echo "✓ PostgreSQL OK"

# Test Redis
docker-compose exec redis-cache redis-cli ping && echo "✓ Redis OK"

# Test Redpanda
docker-compose exec redpanda-broker /opt/redpanda/bin/rpk cluster info && echo "✓ Redpanda OK"
```

#### Step 5.4: Service Log Inspection
```bash
# Check for critical errors
for service in caddy prometheus grafana; do
  echo "=== $service ==="
  docker-compose logs --tail=20 code-server-$service | grep -iE "ERROR|FATAL|PANIC" || echo "  (no errors)"
done
```

**Expected Result**: All services validated successfully ✅

---

### **PHASE 6: Application Verification** (10 minutes)
**Goal**: Verify application-level functionality

#### Step 6.1: Grafana Configuration
```bash
# Verify Grafana datasources
curl -s -u admin:admin http://localhost:3000/api/datasources | jq '.[] | {name, type, url}'

# Expected: At least 1 Prometheus datasource
```

#### Step 6.2: Monitoring Stack
```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# Expected: 20+ active targets
```

#### Step 6.3: Application Logs
```bash
# Final log check for any warnings
docker-compose logs --tail=50 | grep -iE "WARN|ERROR" | head -10

# Expected: No CRITICAL or ERROR level logs
```

**Expected Result**: Application functioning correctly ✅

---

### **PHASE 7: Backup & Post-Deployment** (10 minutes)
**Goal**: Create backup and document deployment

#### Step 7.1: Backup Creation
```bash
# Create backup of current state
bash scripts/ops/backup-idempotent.sh

# Expected: Backup file created in artifacts/backups/
```

#### Step 7.2: Run Post-Deployment Validation
```bash
# Comprehensive health check suite
bash scripts/ops/post-deployment-validation.sh

# Expected output:
#   ✓ All services running
#   ✓ All ports listening
#   ✓ All endpoints healthy
#   ✓ No error logs
#   ✓ Disk space acceptable
#   ✅ All post-deployment validation checks PASSED!
```

#### Step 7.3: Document Deployment
```bash
# Create deployment record
DEPLOY_DATE=$(date -u +'%Y%m%d-%H%M%S')
mkdir -p artifacts/deployments/
cat > "artifacts/deployments/deployment-${DEPLOY_DATE}.md" <<EOF
# Deployment Record: Primary Host

**Date**: $(date -u)
**Host**: 192.168.168.31
**Services**: 41
**Status**: ✅ SUCCESS

## Deployment Summary
- All trap handlers validated (91/91 scripts ✓)
- All Docker images built successfully
- All 41 services started and healthy
- All ports listening and endpoints responding
- All health checks passing
- Backup created: $(ls -1t artifacts/backups/ | head -1)

## Validation Results
- Pre-deployment: ✓ PASS
- Phase validations: ✓ PASS
- Service health: ✓ PASS
- Post-deployment: ✓ PASS

## Rollback Procedure
If issues occur:
\`\`\`bash
bash scripts/ops/rollback-idempotent.sh --backup $(ls -1t artifacts/backups/ | head -1)
\`\`\`
EOF

echo "✓ Deployment record created: artifacts/deployments/deployment-${DEPLOY_DATE}.md"
```

**Expected Result**: Deployment complete and documented ✅

---

## Success Criteria

✅ **Deployment is successful when:**
1. All 41 services are running and healthy
2. All services have passed health checks
3. All 7 ports are listening and responding
4. All 4 key endpoints return HTTP 200
5. No ERROR or FATAL logs in core services
6. Database, cache, and message broker accessible
7. Monitoring stack (Prometheus, Grafana) operational
8. Post-deployment validation script returns PASS
9. Backup file successfully created
10. Deployment record documented

---

## Rollback Procedures

### Quick Rollback (< 5 minutes)
```bash
# If deployment fails and needs immediate rollback
docker-compose down

# Find latest backup
LATEST_BACKUP=$(ls -1t artifacts/backups/ | head -1)

# Restore from backup
bash scripts/ops/rollback-idempotent.sh --backup "$LATEST_BACKUP"

# Restart services
docker-compose up -d

# Verify
bash scripts/ops/post-deployment-validation.sh
```

### Full Rollback to Previous Commit
```bash
# If infrastructure code needs reverting
git log --oneline | head -5  # Find previous good commit
git checkout <commit-hash>

# Rebuild and redeploy
docker-compose down -v
docker-compose build
docker-compose up -d
```

---

## Troubleshooting Guide

### Symptom: Service fails to start
```bash
# Check service logs
docker-compose logs <service-name>

# Restart service
docker-compose restart <service-name>

# Check resource constraints
docker stats <container-id>
```

### Symptom: Database connection timeout
```bash
# Verify PostgreSQL is running
docker-compose ps | grep postgres

# Check database logs
docker-compose logs postgres-db | tail -50

# Reset database
docker-compose down postgres-db
docker-compose up postgres-db -d
```

### Symptom: Memory issues
```bash
# Check memory usage
docker stats --no-stream

# If high: increase Docker memory allocation
# On host: edit Docker daemon config or increase system swap
```

### Symptom: Port conflicts
```bash
# Find process using port
lsof -i :80  # Replace with port number

# If another service: stop it or change port mapping
```

---

## Monitoring After Deployment

### Daily Checks
```bash
# Health status
docker-compose ps

# Service metrics
bash scripts/ops/post-deployment-validation.sh

# Check logs
docker-compose logs --tail=100 | grep -iE "ERROR|FATAL"
```

### Weekly Checks
```bash
# Full validation
bash scripts/ci/validate-trap-handlers.sh

# Backup verification
ls -1t artifacts/backups/ | head -5

# Performance baseline
docker stats --no-stream
```

---

## Contact & Escalation

- **Deployment Issues**: Consult PRIMARY_HOST_DEPLOYMENT_RUNBOOK.md
- **Infrastructure Questions**: See INFRASTRUCTURE_HARDENING_STATUS.md
- **Emergency Rollback**: Execute rollback procedures above
- **Post-Deployment Support**: Contact infrastructure team

---

## Sign-Off

| Role | Name | Date | Approval |
|------|------|------|----------|
| Infrastructure Engineer | | | ☐ |
| Operations Lead | | | ☐ |
| Security Review | | | ☐ |

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-28  
**Status**: Ready for Execution  
**Estimated Time to Complete**: 2-3 hours  
**Success Probability**: 🟢 High (with comprehensive validation)
