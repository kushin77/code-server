# Primary Host Deployment Runbook
**Version**: 1.0  
**Date**: 2026-04-28  
**Status**: Ready for Production Deployment

## Executive Summary
This runbook provides step-by-step instructions for deploying the code-server infrastructure on the primary host (192.168.168.31) with all hardening measures implemented.

## Pre-Deployment Checklist

### Infrastructure Requirements
- [ ] Primary host reachable via SSH (192.168.168.31)
- [ ] Docker and Docker Compose installed (version check)
- [ ] Adequate disk space: 50+ GB available
- [ ] Network connectivity verified (upstream DNS, external repos)
- [ ] SSH key configured for passwordless access

### Configuration Requirements
- [ ] `.env.infrastructure` file present with all required variables
- [ ] Terraform state backend configured (if using Terraform)
- [ ] TLS certificates available or Let's Encrypt configured
- [ ] Database passwords and secrets generated
- [ ] OAuth2 credentials configured

### Validation Requirements
- [ ] All scripts have trap handlers (`scripts/ci/lint-error-handling.sh PASS`)
- [ ] Docker Compose syntax validated
- [ ] Terraform configuration validated
- [ ] Environment variables SSOT verified

## Deployment Steps

### Phase 1: Environment Preparation (10 minutes)

#### Step 1.1: Connect to Primary Host
```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server
```

#### Step 1.2: Verify Docker Installation
```bash
docker --version
docker-compose --version
# Expected: Docker v25+ and Docker Compose v2+
```

#### Step 1.3: Load Environment Configuration
```bash
source .env.infrastructure

# Verify critical variables
echo "PRIMARY_HOST: $PRIMARY_HOST"
echo "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:0:5}***"
echo "APEX_DOMAIN: $APEX_DOMAIN"
```

### Phase 2: Pre-Deployment Validation (15 minutes)

#### Step 2.1: Validate Error Handling in Scripts
```bash
bash scripts/ci/validate-trap-handlers.sh
# Expected: All trap handlers validated successfully
```

#### Step 2.2: Validate Docker Compose Configuration
```bash
docker-compose -f docker-compose.yml config > /dev/null
docker-compose -f docker-compose.enterprise.yml config > /dev/null
# Expected: No errors
```

#### Step 2.3: Validate Environment SSOT
```bash
bash scripts/ci/validate-config-ssot.sh
# Expected: Configuration validation passed
```

#### Step 2.4: Check Disk Space
```bash
df -h /
# Expected: At least 50GB available
```

### Phase 3: Service Initialization (20 minutes)

#### Step 3.1: Build Docker Images
```bash
docker-compose build --no-cache
# Time: ~10-15 minutes depending on network
# Expected: All services built successfully
```

#### Step 3.2: Start Init Containers (if applicable)
```bash
# Start only init containers
docker-compose up code-server-postgres-init \
                    code-server-redis-init \
                    code-server-redpanda-init \
                    --abort-on-container-exit

# Expected: All init containers exit with status 0
```

#### Step 3.3: Start Core Services
```bash
docker-compose up -d
# Expected: All 41 services start without errors
```

### Phase 4: Service Validation (30 minutes)

#### Step 4.1: Wait for Services to Become Ready
```bash
# Monitor with explicit timeout
timeout 600 bash scripts/ops/verify-service-health.sh

# Expected:
# - All services reporting healthy within 5 minutes
# - No services in "starting" or "unhealthy" state
```

#### Step 4.2: Verify Key Service Endpoints
```bash
# Check Caddy Gateway
curl -s http://localhost:80/health | jq .

# Check OAuth2 Proxy
curl -s http://localhost:4180/ping

# Check Prometheus
curl -s http://localhost:9090/-/healthy

# Check Grafana
curl -s -u admin:admin http://localhost:3000/api/health

# Expected: All return 200 or healthy status
```

#### Step 4.3: Verify Database Connectivity
```bash
docker-compose exec postgres-db \
  pg_isready -U postgres

# Expected: accepting connections
```

#### Step 4.4: Verify Message Broker Connectivity
```bash
docker-compose exec redpanda-broker \
  /opt/redpanda/bin/rpk cluster info

# Expected: Cluster information displayed with 1 broker
```

### Phase 5: Application Verification (20 minutes)

#### Step 5.1: Check Application Logs
```bash
# Check for errors in critical services
for service in code-server-caddy \
               code-server-oauth2-proxy \
               code-server-prometheus \
               code-server-grafana; do
  echo "=== $service ===" 
  docker-compose logs --tail=20 $service | grep -iE "error|fatal|panic" || echo "No errors"
done

# Expected: No FATAL or ERROR level logs
```

#### Step 5.2: Verify Monitoring Stack
```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data | keys'

# Expected: Multiple targets in "up" state
```

#### Step 5.3: Test Grafana Dashboard
```bash
# Access Grafana
curl -s -u admin:admin http://localhost:3000/api/datasources

# Expected: At least one datasource configured (Prometheus)
```

### Phase 6: Health Checks & Monitoring Setup (15 minutes)

#### Step 6.1: Verify Health Check Configuration
```bash
# Check that all services have health checks
docker ps --format "table {{.Names}}\t{{.State}}" | grep -v "Exited"

# Expected: All services showing healthy or running state
```

#### Step 6.2: Enable Monitoring Dashboards
```bash
# If Grafana dashboards need to be imported:
# 1. Log into Grafana: http://<PRIMARY_HOST>:3000
# 2. Navigate to Dashboards > Import
# 3. Import dashboard JSON files from grafana/dashboards/

# Expected: Dashboards appear in Grafana
```

#### Step 6.3: Configure Alerting Rules
```bash
# Verify Prometheus alerting configuration
curl -s http://localhost:9090/api/v1/rules | jq '.data | length'

# Expected: At least 1 alert rule defined
```

### Phase 7: Backup & Snapshot (10 minutes)

#### Step 7.1: Create Backup
```bash
bash scripts/ops/backup-idempotent.sh

# Expected: Backup created in artifacts/backups/
```

#### Step 7.2: Document Deployment
```bash
# Create deployment record
cat > artifacts/deployments/deployment-$(date +%Y%m%d-%H%M%S).txt <<EOF
Deployment Date: $(date -u)
Primary Host: $PRIMARY_HOST
Services Deployed: 41
Status: ✅ SUCCESS
Validated By: $(whoami)
EOF
```

## Rollback Procedures

### Quick Rollback (< 5 minutes)
```bash
# Stop all services
docker-compose down

# Restore from backup
bash scripts/ops/rollback-idempotent.sh --backup <backup-file>

# Restart services
docker-compose up -d
```

### Full Rollback to Previous Version
```bash
# Stop services
docker-compose down -v

# Reset to previous commit
git checkout <previous-commit>

# Restart with previous configuration
docker-compose build
docker-compose up -d
```

## Post-Deployment Verification

### Daily Checks
- [ ] All 41 services reporting healthy
- [ ] No error logs in critical services
- [ ] Prometheus scraping all targets
- [ ] Grafana dashboards displaying metrics
- [ ] Database backups running

### Weekly Checks
- [ ] Verify replica host reachability (when available)
- [ ] Test disaster recovery procedures
- [ ] Review security logs
- [ ] Check disk usage trends

### Monthly Checks
- [ ] Dependency security audit
- [ ] Performance baseline comparison
- [ ] Backup restoration test
- [ ] Documentation updates

## Troubleshooting

### Service Fails to Start
```bash
# Check service logs
docker-compose logs <service-name>

# Check health status
docker inspect <container-id> | jq '.State'

# Restart service
docker-compose restart <service-name>
```

### Database Connection Issues
```bash
# Check PostgreSQL status
docker-compose exec postgres-db psql -U postgres -c "SELECT version();"

# Reset database
docker-compose down -v
docker-compose up postgres-db -d
```

### Memory/Resource Issues
```bash
# Check resource usage
docker stats

# Increase limits in docker-compose.yml
# and restart service
docker-compose restart <service-name>
```

### Network Issues
```bash
# Check network connectivity
docker network ls
docker network inspect code-server_default

# Verify DNS resolution
docker-compose exec <service-name> nslookup <hostname>
```

## Success Criteria

✅ **Deployment is successful when:**
- All 41 services are running and healthy
- No services are restarting or failing
- Database is accessible and initialized
- Message broker is operational
- Monitoring dashboards are displaying metrics
- All health checks pass
- No error logs in critical services

## Contact & Escalation

- **Infrastructure Team**: escalations@example.com
- **On-Call Support**: See PagerDuty schedule
- **Incident Response**: See incident-response runbook

---
**Last Updated**: 2026-04-28  
**Next Review**: 2026-05-28 (Monthly)  
**Maintained By**: Infrastructure Team
