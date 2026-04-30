# Hermes Agent Portal - Operations Manual

**Date:** April 30, 2026  
**Version:** 1.0.0  
**Status:** ✅ PRODUCTION READY  
**Platform:** kushnir.cloud  

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Daily Operations](#daily-operations)
3. [Monitoring & Alerts](#monitoring--alerts)
4. [Troubleshooting](#troubleshooting)
5. [Maintenance](#maintenance)
6. [Backup & Recovery](#backup--recovery)
7. [Performance Optimization](#performance-optimization)
8. [Security](#security)

---

## Getting Started

### Quick Start (5 minutes)

```bash
# 1. Navigate to code-server directory
cd /home/akushnir/code-server

# 2. Deploy services
./deploy-production.sh

# 3. Wait for services to start (1-2 minutes)
docker-compose -f docker-compose.enterprise.yml ps

# 4. Access dashboard
# Open browser: https://kushnir.cloud
# Sign in with Google OAuth
```

### Service Architecture

```
Users (Browser)
    ↓
HTTPS (TLS 1.2+, Caddyfile)
    ├── / → Appsmith Dashboard (port 8084)
    ├── /ide → code-server IDE (port 8080)
    └── /api/hermes → REST API (port 8000)
         └── All 250 Hermes phases
```

### Initial Access

| Component | URL | Auth | Status |
|-----------|-----|------|--------|
| Dashboard | https://kushnir.cloud | OAuth2 | ✅ Live |
| Dashboard Alt | https://kushnir.cloud/paperclip | OAuth2 | ✅ Live |
| IDE | https://kushnir.cloud/ide | OAuth2 | ✅ Live |
| API Health | https://kushnir.cloud/api/hermes/health | Token | ✅ Live |

---

## Daily Operations

### Morning Checklist

```bash
# 1. Verify all services are running
docker-compose -f docker-compose.enterprise.yml ps

# Expected output: All services "Up"

# 2. Check API health
curl -k https://kushnir.cloud/api/hermes/health | jq .

# Expected: {"status": "healthy", "service": "hermes-integration"}

# 3. Monitor resource usage
docker stats --no-stream code-server-appsmith code-server-hermes-integration

# 4. Review recent logs
docker-compose -f docker-compose.enterprise.yml logs --tail 50
```

### Access Dashboard

```bash
# Option 1: Direct HTTPS
https://kushnir.cloud

# Option 2: Alternative URL
https://kushnir.cloud/paperclip

# Option 3: localhost (if SSH tunneling)
ssh -L 8443:kushnir.cloud:443 akushnir@192.168.168.31
# Then: https://localhost:8443
```

### Test Phases via Dashboard

1. Navigate to https://kushnir.cloud
2. Complete OAuth login (Google)
3. Select "Phase Management" page
4. Choose phase 250 from dropdown
5. Click "Get Phase Info" (retrieves data)
6. Click "Run Tests" (executes tests)
7. Click "Quality Check" (runs quality validation)
8. Click "Create Commit" (creates git commit)

### Test via API (Command Line)

```bash
# Get metrics
curl -k https://kushnir.cloud/api/hermes/metrics | jq .

# Get phase info
curl -k https://kushnir.cloud/api/hermes/phases/250 | jq .

# Run phase tests
curl -k -X POST https://kushnir.cloud/api/hermes/phases/250/test | jq .

# Get commit history
curl -k https://kushnir.cloud/api/hermes/git/log | jq '.commits | length'
```

---

## Monitoring & Alerts

### Real-time Monitoring

```bash
# Watch service status every 5 seconds
watch -n 5 'docker-compose -f docker-compose.enterprise.yml ps'

# Monitor resource usage
docker stats

# Monitor container logs (all services)
docker-compose -f docker-compose.enterprise.yml logs -f

# Monitor specific service
docker logs -f code-server-appsmith
docker logs -f hermes-integration
docker logs -f code-server-postgres
```

### Health Check Endpoints

```bash
# Service health (internal)
curl http://hermes-integration:8000/health

# Platform metrics (internal)
curl http://hermes-integration:8000/metrics

# API health (external)
curl -k https://kushnir.cloud/api/hermes/health

# Full status report
curl -k https://kushnir.cloud/api/hermes/status | jq .
```

### Key Metrics to Monitor

```bash
# Platform metrics
{
  "total_phases": 250,
  "passed_tests": 2542,
  "failed_tests": 0,
  "quality_score": 100,
  "status": "Production Ready"
}

# Service health
{
  "status": "healthy",
  "service": "hermes-integration",
  "uptime_seconds": 86400,
  "version": "1.0.0"
}
```

### Performance Baseline

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Dashboard Load | < 2s | > 5s |
| API Response | < 500ms | > 2s |
| CPU Usage | < 50% | > 80% |
| Memory Usage | < 60% | > 85% |
| Disk Usage | < 60% | > 85% |
| DB Connections | < 10 | > 20 |

---

## Troubleshooting

### Common Issues & Solutions

#### 1. "Connection refused" to Dashboard

**Symptoms:** `curl: (7) Failed to connect to kushnir.cloud port 443`

**Solutions:**
```bash
# Check if services are running
docker-compose -f docker-compose.enterprise.yml ps

# Restart services if needed
docker-compose -f docker-compose.enterprise.yml down
docker-compose -f docker-compose.enterprise.yml up -d

# Verify port is accessible
netstat -tlnp | grep 443
```

#### 2. OAuth "Invalid client" Error

**Symptoms:** OAuth redirect fails with invalid credentials

**Solutions:**
```bash
# Verify OAuth credentials in .env
cat .env | grep OAUTH_GOOGLE_CLIENT

# Update .env with correct credentials
nano .env

# Restart Appsmith with new credentials
docker-compose -f docker-compose.enterprise.yml restart appsmith

# Wait for restart
sleep 30
```

#### 3. API Returns 502 Bad Gateway

**Symptoms:** `https://kushnir.cloud/api/hermes/health` returns HTTP 502

**Solutions:**
```bash
# Check hermes-integration service
docker ps | grep hermes-integration

# Check service health
docker exec hermes-integration curl http://localhost:8000/health

# View service logs
docker logs hermes-integration | tail -50

# Restart if needed
docker-compose -f docker-compose.enterprise.yml restart hermes-integration
```

#### 4. Dashboard Shows "Connection Error"

**Symptoms:** Dashboard loads but shows "Cannot connect to API"

**Solutions:**
```bash
# Verify API is running
curl http://hermes-integration:8000/health

# Check network connectivity
docker exec code-server-appsmith curl http://hermes-integration:8000/health

# Verify docker network
docker network inspect services

# Restart all services
docker-compose -f docker-compose.enterprise.yml restart
```

#### 5. High Memory Usage

**Symptoms:** Services using > 85% of available memory

**Solutions:**
```bash
# Check memory usage by service
docker stats --no-stream

# Identify high-memory service
# Scale down resources or add more RAM

# Check PostgreSQL for queries
docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT count(*) FROM pg_stat_activity;"

# Optimize database if needed
docker exec code-server-postgres psql -U postgres -d code-server-db -c "VACUUM ANALYZE;"
```

### Emergency Procedures

#### Complete Service Restart

```bash
# Stop all services
docker-compose -f docker-compose.enterprise.yml down

# Wait 10 seconds
sleep 10

# Start all services
docker-compose -f docker-compose.enterprise.yml up -d

# Verify all healthy
watch -n 2 'docker-compose -f docker-compose.enterprise.yml ps'
```

#### Rollback to Previous State

```bash
# Check git history
git log --oneline -10

# If something broke, revert
git revert HEAD

# Redeploy
docker-compose -f docker-compose.enterprise.yml down
docker-compose -f docker-compose.enterprise.yml up -d
```

#### Disk Space Emergency

```bash
# Check disk usage
df -h /home/akushnir/code-server

# Clean Docker
docker system prune -a --volumes

# Clean old logs
docker-compose -f docker-compose.enterprise.yml logs --tail 1000 > logs-backup.txt
# Then clear old logs via Docker config
```

---

## Maintenance

### Daily Maintenance (Automated)

- Service health checks (30s interval per container)
- Log rotation (100MB max per log, keep 10 logs)
- Resource monitoring

### Weekly Maintenance (Manual)

```bash
# 1. Review logs for errors
docker-compose -f docker-compose.enterprise.yml logs > weekly-logs.txt

# 2. Check for updates
docker pull appsmith/appsmith-ce:latest
docker pull codercom/code-server:latest

# 3. Test backup procedure
# (see Backup & Recovery section)

# 4. Review performance metrics
docker stats --no-stream > weekly-stats.txt

# 5. Verify OAuth configuration
curl -k https://kushnir.cloud/health
```

### Monthly Maintenance (Scheduled)

```bash
# 1. Update documentation
# Review and update any operational procedures

# 2. Database maintenance
docker exec code-server-postgres psql -U postgres -d code-server-db << 'EOF'
VACUUM ANALYZE;
REINDEX DATABASE "code-server-db";
EOF

# 3. Log cleanup
# Archive old logs and clean up

# 4. Security updates
# Apply any security patches

# 5. Capacity planning
# Review growth trends and plan for expansion
```

### Quarterly Maintenance (Major)

```bash
# 1. Full system audit
./verify-appsmith-integration.sh

# 2. Disaster recovery drill
# Test full system restore from backup

# 3. Security scanning
# Run security scanners for vulnerabilities

# 4. Documentation refresh
# Update all operational documents

# 5. Team training
# Review procedures with operations team
```

---

## Backup & Recovery

### Backup Procedure

```bash
# 1. Backup PostgreSQL database
docker exec code-server-postgres pg_dump -U postgres code-server-db > db-backup-$(date +%Y%m%d-%H%M%S).sql

# 2. Backup volumes
tar -czf appsmith-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  docker-compose.enterprise.yml Caddyfile .env

# 3. Backup configuration files
tar -czf config-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  Caddyfile docker-compose.enterprise.yml apps/

# 4. Verify backups
ls -lh *-backup-*.* | head -10
```

### Recovery Procedure

```bash
# 1. Stop services
docker-compose -f docker-compose.enterprise.yml down

# 2. Restore volumes
tar -xzf appsmith-backup-YYYYMMDD-HHMMSS.tar.gz

# 3. Restore database
docker-compose -f docker-compose.enterprise.yml up -d code-server-postgres
sleep 30
docker exec code-server-postgres psql -U postgres < db-backup-YYYYMMDD-HHMMSS.sql

# 4. Start all services
docker-compose -f docker-compose.enterprise.yml up -d

# 5. Verify recovery
docker-compose -f docker-compose.enterprise.yml ps
curl -k https://kushnir.cloud/api/hermes/health
```

### Backup Retention Policy

- **Daily backups:** Keep 7 days
- **Weekly backups:** Keep 4 weeks
- **Monthly backups:** Keep 12 months
- **Offsite backup:** Keep latest 3 months

---

## Performance Optimization

### Appsmith Optimization

```bash
# Enable caching
docker exec code-server-appsmith redis-cli CONFIG SET maxmemory 1gb
docker exec code-server-appsmith redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Monitor connections
docker exec code-server-appsmith redis-cli INFO stats
```

### Database Optimization

```bash
# Check slow queries
docker exec code-server-postgres psql -U postgres -d code-server-db -c "
  SELECT query, calls, total_time FROM pg_stat_statements 
  ORDER BY total_time DESC LIMIT 10;
"

# Create indexes
docker exec code-server-postgres psql -U postgres -d code-server-db << 'EOF'
CREATE INDEX idx_phase_number ON phases(phase_number);
CREATE INDEX idx_test_phase_id ON tests(phase_id);
CREATE INDEX idx_commit_timestamp ON commits(created_at);
EOF

# Vacuum and analyze
docker exec code-server-postgres psql -U postgres -d code-server-db -c "VACUUM ANALYZE;"
```

### Network Optimization

```bash
# Verify reverse proxy caching headers
curl -I https://kushnir.cloud/api/hermes/metrics | grep -i "cache-control\|etag"

# Monitor connection count
netstat -an | grep ESTABLISHED | wc -l

# Check for connection leaks
docker exec code-server-postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
```

---

## Security

### Daily Security Checklist

```bash
# 1. Verify TLS is enforced
curl -I http://kushnir.cloud | head -1
# Expected: 308 Permanent Redirect

# 2. Check certificate validity
echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep -E "subject|issuer|dates"

# 3. Verify OAuth is working
# Open browser and test login

# 4. Review access logs
docker logs code-server-appsmith | grep -i "error\|failed\|unauthorized"
```

### Security Headers Verification

```bash
# Verify all security headers are present
curl -I https://kushnir.cloud | grep -E "Strict-Transport-Security|Content-Security-Policy|X-Content-Type-Options|X-Frame-Options"

# Expected headers:
# Strict-Transport-Security: max-age=31536000
# Content-Security-Policy: default-src 'self'
# X-Content-Type-Options: nosniff
# X-Frame-Options: SAMEORIGIN
```

### Regular Security Updates

```bash
# Check for CVEs
docker image inspect appsmith/appsmith-ce:latest | jq .

# Update images
docker pull appsmith/appsmith-ce:latest
docker pull codercom/code-server:latest

# Restart with new images
docker-compose -f docker-compose.enterprise.yml down
docker-compose -f docker-compose.enterprise.yml up -d
```

---

## Quick Reference

### Essential Commands

```bash
# Start all services
docker-compose -f docker-compose.enterprise.yml up -d

# Stop all services
docker-compose -f docker-compose.enterprise.yml down

# Check status
docker-compose -f docker-compose.enterprise.yml ps

# View logs
docker-compose -f docker-compose.enterprise.yml logs -f

# Restart specific service
docker-compose -f docker-compose.enterprise.yml restart code-server-appsmith

# Access shell in container
docker exec -it code-server-appsmith bash

# Restart single container
docker restart code-server-appsmith

# Check health
curl -k https://kushnir.cloud/api/hermes/health
```

### Contact Information

- **Infrastructure:** Check Docker logs, verify services
- **Deployment Issues:** Review APPSMITH_DEPLOYMENT_GUIDE.md
- **OAuth Issues:** Verify Google OAuth credentials in .env
- **API Issues:** Check hermes-integration service logs
- **Performance:** Monitor docker stats and review database

---

## Support Resources

### Documentation

1. **Deployment Guide:** APPSMITH_DEPLOYMENT_GUIDE.md
2. **Security Integration:** APPSMITH_KUSHNIR_CLOUD_SECURE_INTEGRATION.md
3. **Implementation Summary:** APPSMITH_INTEGRATION_IMPLEMENTATION_SUMMARY.md
4. **Production Package:** PRODUCTION_DEPLOYMENT_PACKAGE.md
5. **This Operations Manual:** OPERATIONS_MANUAL.md

### Useful Links

- Appsmith Docs: https://docs.appsmith.com
- Docker Compose Docs: https://docs.docker.com/compose
- Caddy Docs: https://caddyserver.com/docs
- PostgreSQL Docs: https://www.postgresql.org/docs

---

**Operations Manual Version:** 1.0.0  
**Last Updated:** April 30, 2026  
**Status:** ✅ PRODUCTION READY  
