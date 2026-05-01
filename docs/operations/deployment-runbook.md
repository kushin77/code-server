# Deployment Runbook

**Version**: 2.0  
**Last Updated**: April 24, 2026  
**Audience**: DevOps, Platform Engineers, SREs  

## Overview

This document provides step-by-step procedures for deploying the Paperclip platform to production, staging, and development environments. All deployments follow Infrastructure as Code (IaC) principles with immutable, idempotent operations.

## Prerequisites

### Required Tools
- `git` - Version control
- `docker` & `docker-compose` - Container runtime
- `terraform` - Infrastructure provisioning
- `gh` CLI - GitHub API access
- `bash` - Shell scripting
- SSH access to deployment targets

### Required Access
- GitHub repository push access
- SSH credentials for target hosts
- AWS/Azure credentials for cloud resources (if applicable)
- Vault token for secrets access

### Environment Setup
```bash
# Clone repository
git clone https://github.com/kushin77/code-server.git
cd code-server

# Load environment
source .env.infrastructure

# Verify Git status
git status

# Verify connectivity to deployment targets
ssh ${PRIMARY_HOST} "echo 'Connection OK'"
ssh ${REPLICA_HOST} "echo 'Connection OK'"
```

## Pre-Deployment Checklist

### 1. Code Review & Merge
- [ ] All required PRs reviewed and approved
- [ ] All CI checks passing (tests, lints, security scans)
- [ ] Commits squashed and descriptive
- [ ] Branch merged to `main`
- [ ] Remote synchronized: `git fetch origin && git status`

### 2. Validation Checks
```bash
# Run pre-deployment validation
bash scripts/ci/validate-terraform-version-pins.sh
bash scripts/ci/check-gh-cli-governance.sh all
bash scripts/ci/check-docker-compose-idempotency.sh

# Verify all reports show PASSED
cat artifacts/terraform-version-pins-report.txt
cat artifacts/docker-compose-idempotency-report.json
```

### 3. Backup Current State
```bash
# On both replicas, capture current state
ssh ${PRIMARY_HOST} "docker compose -f /home/akushnir/docker-compose.yml ps > /tmp/pre-deploy-state-primary.txt"
ssh ${REPLICA_HOST} "docker compose -f /home/akushnir/docker-compose.yml ps > /tmp/pre-deploy-state-replica.txt"

# Export database backup
ssh ${PRIMARY_HOST} "pg_dump -h localhost -U postgres paperclip > /tmp/paperclip-backup-$(date +%s).sql"
```

### 4. Create Deployment Issue
```bash
# File GitHub issue for tracking
gh issue create \
  --title "Deployment: $(git log -1 --format=%h) - $(git log -1 --format=%s)" \
  --label deployment,in-progress \
  --body "Deploying commit $(git rev-parse HEAD) to production"
```

## Deployment Procedure

### Phase 1: Staging Deployment (192.168.168.42)

#### Step 1: Pull Latest Code
```bash
# SSH to replica (staging environment)
ssh ${REPLICA_HOST}

# Navigate to deployment directory
cd /home/akushnir/code-server

# Pull latest code
git fetch origin
git checkout main
git pull origin main

# Verify commit
git log -1 --oneline
```

#### Step 2: Load and Validate Configuration
```bash
# Source environment
source .env.infrastructure

# Verify environment variables
echo "API_ENDPOINT: ${API_ENDPOINT}"
echo "PRIMARY_HOST: ${PRIMARY_HOST}"
echo "REPLICA_HOST: ${REPLICA_HOST}"

# Validate docker-compose configuration
docker-compose -f docker-compose.yml config > /dev/null && echo "✓ Config valid"
```

#### Step 3: Prepare Docker Images
```bash
# Build or pull images (if modified)
docker-compose pull

# Verify images downloaded
docker images | grep code-server | head -5
```

#### Step 4: Health Check Pre-Deployment
```bash
# Run infrastructure health check
bash scripts/ci/health-check-post-deploy.sh

# Verify current services running
docker-compose ps

# Check service health endpoints
curl -s http://localhost:3100/health | jq '.'
curl -s http://localhost:3000/health | jq '.' || echo "Grafana may not be running yet"
```

#### Step 5: Deploy to Staging
```bash
# Bring down services gracefully (in reverse dependency order)
docker-compose down

# Verify all containers stopped
docker ps | grep -c "code-server" && echo "ERROR: containers still running" || echo "✓ All stopped"

# Start services with new code
docker-compose up -d

# Wait for services to stabilize (30 seconds)
sleep 30
```

#### Step 6: Staging Validation
```bash
# Verify all services healthy
docker-compose ps

# Check health endpoints
bash scripts/ci/health-check-post-deploy.sh

# Run basic smoke tests
bash scripts/ci/codebase-hygiene-audit.sh

# Check logs for errors
docker-compose logs --tail=50 | grep -i error

# Verify API Gateway responding
curl -I http://localhost:3100/health

# Verify database connectivity
docker exec code-server-postgres-1 pg_isready || echo "Database check pending..."
```

#### Step 7: Staging Sign-Off
```bash
# Record successful staging deployment
echo "Staging deployment validated at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> /tmp/deployment.log

# Note: Keep staging running for 30 minutes to monitor logs
tail -f logs/*.log | grep -i "error\|warn"
```

### Phase 2: Production Deployment (192.168.168.31)

#### Step 1: Pull Latest Code
```bash
ssh ${PRIMARY_HOST}
cd /home/akushnir/code-server
git fetch origin
git checkout main
git pull origin main
git log -1 --oneline
```

#### Step 2: Validation (Same as Staging)
```bash
source .env.infrastructure
docker-compose config > /dev/null && echo "✓ Config valid"
docker-compose pull
bash scripts/ci/health-check-post-deploy.sh
```

#### Step 3: Blue-Green Deployment Preparation

#### Step 3a: Create Secondary Environment (Green)
```bash
# Create a second docker-compose setup for parallel running
export COMPOSE_PROJECT_NAME="code-server-green"
export COMPOSE_API_PORT=3101  # Different port for new environment

# Start green environment
docker-compose -f docker-compose.yml -p code-server-green up -d

# Wait for initialization
sleep 60

# Validate green environment
COMPOSE_PROJECT_NAME=code-server-green docker-compose ps
curl -I http://localhost:3101/health
```

#### Step 3b: Data Sync (If Applicable)
```bash
# Ensure databases are in sync
# Current: Replicas share single database, so no additional sync needed
# Note: PostgreSQL replication handles this automatically
```

#### Step 3c: Run Validation Tests on Green
```bash
# Run comprehensive validation on new environment
export API_ENDPOINT="http://localhost:3101"
bash scripts/ci/codebase-hygiene-audit.sh

# Verify all services responding
curl -s http://localhost:3101/health | jq '.status'
```

#### Step 4: Switch Traffic to Green (Cutover)

#### Step 4a: Caddy Configuration Update
```bash
# Update Caddy config to route to new port
# (If using port mapping, otherwise ensure load balancer updated)

# Validate new configuration
caddy validate --config Caddyfile
```

#### Step 4b: Health Check Green Environment
```bash
# Final pre-switch validation
for i in {1..5}; do
  curl -f http://localhost:3101/health && break || sleep 10
done

# Verify no error spikes in monitoring
curl -s http://localhost:9090/api/v1/query?query='errors_total{job="code-server"}' | jq '.data.result'
```

#### Step 4c: Execute Cutover
```bash
# Bring down blue environment
export COMPOSE_PROJECT_NAME="code-server"
docker-compose down

# Update production environment variable
export COMPOSE_PROJECT_NAME="code-server-green"

# Remove "green" from environment
export COMPOSE_PROJECT_NAME="code-server"
COMPOSE_API_PORT=3100 docker-compose up -d

# Verify production is live
curl -I http://localhost:3100/health
```

#### Step 5: Immediate Post-Deployment Monitoring
```bash
# Monitor logs for errors (30 minutes)
for i in {1..30}; do
  echo "[$(date -u +'%H:%M:%S')] Checking logs..."
  docker-compose logs --since 1m | grep -i "error\|critical" && break || sleep 60
done

# Verify uptime metrics
docker stats --no-stream | grep code-server-

# Check external access
curl -I https://kushnir.cloud/
```

### Phase 3: Rollback Procedure

#### Scenario: Production deployment failed
```bash
# Stop current environment
docker-compose down

# Restore previous docker images
git fetch origin
git checkout <previous-working-commit>
docker-compose pull

# Restart services
docker-compose up -d

# Validate services
bash scripts/ci/health-check-post-deploy.sh

# Notify team
gh issue comment <deployment-issue-number> --body "⚠️ Rollback executed. Previous commit restored."
```

#### Scenario: Database corruption detected
```bash
# Restore database from backup
ssh ${PRIMARY_HOST}

# Stop all services
docker-compose down

# Restore PostgreSQL from backup
pg_restore -h localhost -U postgres -d paperclip /tmp/paperclip-backup-<timestamp>.sql

# Restart services
docker-compose up -d

# Validate data integrity
docker exec code-server-postgres-1 psql -U postgres -d paperclip -c "SELECT count(*) FROM users;"
```

## Health Checks & Monitoring

### Critical Health Checks
```bash
# API Gateway
curl http://${PRIMARY_HOST}:3100/health

# PostgreSQL
docker exec code-server-postgres-1 pg_isready -h localhost

# Redis
redis-cli -h localhost ping

# Prometheus
curl http://${PRIMARY_HOST}:9090/-/healthy

# Grafana
curl -I http://${PRIMARY_HOST}:3000/
```

### SLA Monitoring
```bash
# Check deployment duration
DEPLOYMENT_START=$(date -d "1 hour ago" -u +'%Y-%m-%dT%H:%M:%SZ')
curl -s "http://prometheus:9090/api/v1/query_range?query=up{job='code-server'}&start=${DEPLOYMENT_START}&step=1m" | jq '.data.result'

# Verify < 99.9% downtime acceptable for production
# Target RTO: 15 minutes, Target RPO: 1 hour
```

## Post-Deployment Verification

### Verification Checklist
- [ ] All services showing `healthy` status
- [ ] No error spikes in monitoring dashboards
- [ ] User-facing endpoints responding correctly
- [ ] Database replication lag < 100ms
- [ ] API latency < 500ms (p95)
- [ ] No resource constraints (CPU < 80%, Memory < 85%)

### User Communication
```bash
# Post deployment status update
gh issue comment <deployment-issue-number> \
  --body "✅ Deployment complete. All health checks passed. Monitoring for 1 hour."

# Close deployment issue when stable
gh issue close <deployment-issue-number> \
  --comment "Deployment successful and stable for >1 hour."
```

## Troubleshooting Guide

### Issue: Services not starting
```bash
# Check logs for startup errors
docker-compose logs --tail=100

# Verify port availability
netstat -tulpn | grep -E ":3100|:3000|:5432"

# Check disk space
df -h | grep -E "/$|/var"

# Solution: Free resources and retry
docker system prune -a --volumes --force
docker-compose up -d
```

### Issue: Database connection errors
```bash
# Verify PostgreSQL is running
docker ps | grep postgres

# Check PostgreSQL logs
docker logs code-server-postgres-1 --tail=50

# Verify network connectivity
docker exec code-server-postgres-1 pg_isready

# Solution: Check credentials in .env.infrastructure
source .env.infrastructure
echo "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}"
```

### Issue: High API latency after deployment
```bash
# Check database query performance
docker exec code-server-postgres-1 psql -U postgres -d paperclip -c "EXPLAIN ANALYZE SELECT * FROM activities LIMIT 1;"

# Monitor slow queries
docker logs code-server-postgres-1 | grep "duration:"

# Solution: Run query optimization or add missing indexes
bash scripts/db/optimize-queries.sh
```

### Issue: Memory leaks in application services
```bash
# Monitor memory usage over time
watch -n 5 'docker stats --no-stream | grep code-server'

# Check for goroutine leaks (Node.js)
curl http://localhost:3100/debug/pprof/goroutine

# Solution: Rolling restart of affected service
docker-compose restart code-server-api
```

## Deployment Failure Scenarios

| Scenario | Detection | Action | RTO |
|----------|-----------|--------|-----|
| Service fails to start | Health check timeout | Rollback to previous commit | 5 min |
| Database corruption | Connection errors | Restore from backup | 15 min |
| High latency spike | API response time > 2s | Check resource usage, scale horizontally | 10 min |
| Memory exhaustion | OOM killer | Restart affected service | 3 min |
| Network partition | Replica sync lag > 1s | Automatic failover | 1 min |

## Deployment Frequency & Windows

### Current Schedule
- **Deployments**: On-demand (via Git push to main)
- **Maintenance Windows**: None (zero-downtime deployments)
- **Rollback Windows**: Immediate (within 30 seconds)

### Future Schedule (Planned)
- **Canary Deployments**: 10% traffic to new version for 1 hour
- **Blue-Green Windows**: Daily 2-4 AM UTC
- **Maintenance: Every other Thursday, 2-4 AM UTC

## Appendix: Useful Commands

```bash
# Quick deployment status
docker-compose ps

# View recent logs
docker-compose logs --tail=100

# Restart single service
docker-compose restart code-server-api

# Execute command in container
docker exec code-server-postgres-1 psql -U postgres

# Access container shell
docker exec -it code-server-api /bin/bash

# Monitor resource usage
docker stats

# View network connections
docker network ls
docker network inspect code-server_default

# Cleanup unused images
docker image prune -a

# Force update (no cache)
docker-compose pull --no-cache
docker-compose build --no-cache
docker-compose up -d
```

## Related Documentation
- [Architecture Overview](../architecture/OVERVIEW.md)
- [Security Guide](../security/SECURITY-GUIDE.md)
- [Operations Procedures](../operations/)
