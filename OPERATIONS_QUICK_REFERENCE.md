# Hermes Agent Portal - Operational Quick Reference

**Last Updated:** April 30, 2026  
**Version:** 1.0  
**Audience:** Operations Team  

---

## Quick Navigation

**Common Tasks:**
- [Daily Startup](#daily-startup) - Start services in the morning
- [Daily Health Check](#daily-health-check) - Verify system is operational
- [View Logs](#view-logs) - Check service logs
- [Restart Services](#restart-services) - Restart failed services
- [Emergency Shutdown](#emergency-shutdown) - Stop all services

**Maintenance Tasks:**
- [Backup System](#backup-system) - Create full backup
- [Restore from Backup](#restore-from-backup) - Restore previous state
- [Update Services](#update-services) - Update to latest version
- [Performance Optimization](#performance-optimization) - Tune system

**Monitoring Tasks:**
- [Real-Time Monitoring](#real-time-monitoring) - Watch live metrics
- [Generate Report](#generate-report) - Create performance report
- [Alert Configuration](#alert-configuration) - Set up alerts

---

## Daily Operations

### Daily Startup

**Time Required:** 5 minutes

```bash
# Check if services are already running
docker-compose -f docker-compose.enterprise.yml ps

# If not running, start them
docker-compose -f docker-compose.enterprise.yml up -d

# Wait for services to be healthy (2-3 minutes)
sleep 180

# Verify all services healthy
docker-compose -f docker-compose.enterprise.yml ps
# Expected: All show "Up (healthy)"

# Test API
curl -k https://kushnir.cloud/api/hermes/health
# Expected: {"status": "healthy", "service": "hermes-integration"}

# Verify in browser
# Navigate: https://kushnir.cloud
# Expected: Appsmith login page loads
```

### Daily Health Check

**Time Required:** 2 minutes

```bash
# Quick health summary
./validate-deployment.sh

# Or run comprehensive health monitor
./monitor-health.sh 10 60
# This will monitor every 10 seconds for 1 minute
```

### View Logs

**Time Required:** 1-2 minutes

```bash
# View last 50 lines from all services
docker-compose -f docker-compose.enterprise.yml logs --tail 50

# View specific service logs
docker logs -f appsmith              # Appsmith portal
docker logs -f hermes-integration    # API service
docker logs -f code-server-ide       # IDE service
docker logs -f code-server-postgres  # Database
docker logs -f code-server-redis     # Cache

# View logs from last hour
docker-compose -f docker-compose.enterprise.yml logs --since 60m

# Search for errors
docker-compose -f docker-compose.enterprise.yml logs | grep -i "error\|failed"
```

### Restart Services

**Time Required:** 5 minutes

**Restart all services:**
```bash
docker-compose -f docker-compose.enterprise.yml restart
sleep 180  # Wait for services to stabilize
```

**Restart specific service:**
```bash
# Appsmith
docker-compose -f docker-compose.enterprise.yml restart appsmith

# API
docker-compose -f docker-compose.enterprise.yml restart hermes-integration

# IDE
docker-compose -f docker-compose.enterprise.yml restart code-server-ide

# Database (careful!)
docker-compose -f docker-compose.enterprise.yml restart code-server-postgres

# Cache
docker-compose -f docker-compose.enterprise.yml restart code-server-redis
```

### Emergency Shutdown

**Time Required:** 1 minute

**Stop all services immediately:**
```bash
# Graceful shutdown (preferred)
docker-compose -f docker-compose.enterprise.yml down

# Or use automation script
./backup-recovery.sh emergency

# Verify all stopped
docker-compose -f docker-compose.enterprise.yml ps
# Expected: Empty output (no running containers)
```

---

## Maintenance Operations

### Backup System

**Time Required:** 5-10 minutes

```bash
# Create full backup (database, config, volumes)
./backup-recovery.sh backup

# Expected output:
# [OK] Backup completed successfully
# Backup ID: backup_20260430_120000
# Size: 150MB

# List available backups
./backup-recovery.sh list
```

### Restore from Backup

**Time Required:** 10-15 minutes

```bash
# List backups
./backup-recovery.sh list

# Restore specific backup (this will stop services)
./backup-recovery.sh restore backup_20260430_120000

# Verify restoration
curl -k https://kushnir.cloud/api/hermes/health
```

### Update Services

**Time Required:** 10-15 minutes

```bash
# Check for latest images
docker pull appsmith/appsmith-ce:latest
docker pull codercom/code-server:latest
docker pull postgres:latest
docker pull redis:latest

# Update docker-compose to use latest tags (if configured)
nano docker-compose.enterprise.yml

# Restart services with new images
docker-compose -f docker-compose.enterprise.yml up -d

# Verify updates
docker-compose -f docker-compose.enterprise.yml ps
```

### Performance Optimization

**Time Required:** 15 minutes

```bash
# Analyze current performance
./optimize-performance.sh analyze

# Apply optimizations
./optimize-performance.sh optimize

# Generate performance report
./optimize-performance.sh report
```

---

## Monitoring Operations

### Real-Time Monitoring

**Time Required:** Continuous

```bash
# Monitor every 30 seconds for 1 hour
./monitor-health.sh 30 3600

# Monitor every 5 seconds indefinitely (Ctrl+C to stop)
./monitor-health.sh 5 0

# Watch specific metrics
watch -n 2 'docker stats --no-stream'

# Monitor API response time
watch -n 5 'curl -s -k -w "Response time: %{time_total}s\n" -o /dev/null https://kushnir.cloud/api/hermes/health'
```

### Generate Report

**Time Required:** 5 minutes

```bash
# Text report
./validate-deployment.sh text

# JSON report (for parsing)
./validate-deployment.sh json

# HTML report (for viewing in browser)
./validate-deployment.sh html
# View: open deployment-reports/validation_*.html

# Performance report
./optimize-performance.sh report
# View: open performance-reports/performance_report_*.txt
```

### Alert Configuration

**Production alert thresholds:**

```
CPU Usage      >80%   - ALERT
Memory Usage   >85%   - ALERT
Disk Usage     >90%   - ALERT
API Response   >2s    - WARN
Error Rate     >1%    - ALERT
Database Conn  >100   - ALERT
```

**Check current metrics:**
```bash
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}"
df -h /home
```

---

## Troubleshooting Scenarios

### Scenario 1: API Not Responding

```bash
# 1. Check if container is running
docker ps | grep hermes-integration

# 2. Check logs
docker logs hermes-integration | tail -20

# 3. Restart service
docker-compose -f docker-compose.enterprise.yml restart hermes-integration

# 4. Verify
curl -k https://kushnir.cloud/api/hermes/health

# 5. If still failing, check database
docker logs code-server-postgres | tail -20
```

### Scenario 2: Dashboard Won't Load

```bash
# 1. Check Appsmith container
docker ps | grep appsmith

# 2. Check logs
docker logs appsmith | tail -50

# 3. Restart Appsmith
docker-compose -f docker-compose.enterprise.yml restart appsmith

# 4. Wait 60 seconds
sleep 60

# 5. Try accessing dashboard
curl -i -k https://kushnir.cloud/
```

### Scenario 3: Database Connection Failed

```bash
# 1. Check if database is running
docker ps | grep postgres

# 2. Test database connectivity
docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT 1;"

# 3. Check disk space (database might be full)
df -h /home

# 4. Check logs
docker logs code-server-postgres | tail -50

# 5. Restart database
docker-compose -f docker-compose.enterprise.yml restart code-server-postgres

# 6. Wait 30 seconds for database to come up
sleep 30
```

### Scenario 4: Disk Space Running Out

```bash
# 1. Check disk usage
df -h

# 2. Find large files
du -sh /* | sort -h | tail -10

# 3. Clean Docker images/containers
docker system prune -a

# 4. Check log files
du -sh /home/akushnir/code-server/monitoring-logs/*
du -sh /home/akushnir/code-server/deployment-reports/*

# 5. Archive old logs (optional)
tar -czf logs_archive_$(date +%Y%m%d).tar.gz monitoring-logs/
rm -rf monitoring-logs/*.log
```

### Scenario 5: Memory Usage Critical

```bash
# 1. Check which containers are using memory
docker stats --no-stream --format "{{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | sort

# 2. Clear cache
docker exec code-server-redis redis-cli FLUSHALL

# 3. Restart high-memory service
docker-compose -f docker-compose.enterprise.yml restart <service-name>

# 4. Monitor memory after restart
docker stats --no-stream
```

---

## Common Commands Cheat Sheet

```bash
# Service Management
docker-compose -f docker-compose.enterprise.yml ps          # List services
docker-compose -f docker-compose.enterprise.yml up -d       # Start services
docker-compose -f docker-compose.enterprise.yml down        # Stop services
docker-compose -f docker-compose.enterprise.yml logs -f     # View logs
docker-compose -f docker-compose.enterprise.yml restart     # Restart all

# Health Checks
curl -k https://kushnir.cloud/api/hermes/health            # API health
curl -k https://kushnir.cloud/                             # Dashboard
nslookup kushnir.cloud                                      # DNS check
echo | openssl s_client -connect kushnir.cloud:443          # SSL check

# Monitoring
./monitor-health.sh 30 3600                                 # Real-time monitor
./validate-deployment.sh                                    # Full validation
docker stats --no-stream                                    # Resource usage
df -h /home                                                 # Disk usage

# Backup & Recovery
./backup-recovery.sh backup                                 # Create backup
./backup-recovery.sh list                                   # List backups
./backup-recovery.sh restore backup_20260430_120000        # Restore
./backup-recovery.sh emergency                              # Emergency stop

# Performance
./optimize-performance.sh analyze                           # Analyze
./optimize-performance.sh optimize                          # Optimize
./optimize-performance.sh report                            # Report

# Database
docker exec code-server-postgres psql -U postgres -d code-server-db -c "VACUUM ANALYZE;"
docker exec code-server-postgres pg_dump -U postgres code-server-db > backup.sql

# Replica
./deploy-replica.sh 192.168.168.31 192.168.168.42          # Deploy replica
```

---

## Daily Checklist

**Morning (Start of Day):**
- [ ] Start services: `docker-compose -f docker-compose.enterprise.yml up -d`
- [ ] Wait 3 minutes for startup
- [ ] Verify health: `./validate-deployment.sh`
- [ ] Check logs for errors: `docker-compose -f docker-compose.enterprise.yml logs | grep -i error`

**Throughout Day:**
- [ ] Monitor every 2 hours: `./monitor-health.sh 30 300`
- [ ] Check error logs hourly
- [ ] Verify API responsiveness

**End of Day:**
- [ ] Review logs for issues: `docker-compose -f docker-compose.enterprise.yml logs --since 12h`
- [ ] Create backup if changes made: `./backup-recovery.sh backup`
- [ ] Document any issues in incident log

**Weekly (Friday):**
- [ ] Full backup: `./backup-recovery.sh backup`
- [ ] Performance optimization: `./optimize-performance.sh optimize`
- [ ] Performance report: `./optimize-performance.sh report`
- [ ] Review week's logs and incidents

**Monthly (End of Month):**
- [ ] Test recovery procedure: `./backup-recovery.sh restore <backup-id>`
- [ ] Archive old logs
- [ ] Review system performance trends
- [ ] Plan any upgrades or maintenance

---

## Contact & Escalation

**For Issues:**
1. Check this quick reference
2. Review troubleshooting scenarios
3. Check service logs: `docker-compose -f docker-compose.enterprise.yml logs`
4. Run validation: `./validate-deployment.sh`

**For Urgent Issues:**
- Emergency shutdown: `./backup-recovery.sh emergency`
- Recovery procedure: `./backup-recovery.sh recover`
- Contact: Development team

---

**This quick reference provides fast access to common operations. Keep this guide handy for daily use.**

**For detailed procedures, refer to:**
- OPERATIONAL_HANDOFF_FOR_OPS_TEAM.md
- OPERATIONS_MANUAL.md
- POST_DEPLOYMENT_VERIFICATION_CHECKLIST.md
