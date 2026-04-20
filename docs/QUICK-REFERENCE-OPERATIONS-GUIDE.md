# Quick Reference Guide - Operations & Support
## kushin77/code-server Deployment #950

---

## 🚀 Quick Start

### SSH to Production
```bash
ssh akushnir@192.168.168.31    # Primary host
ssh akushnir@192.168.168.42    # Replica host
```

### Basic Service Commands
```bash
# View all services
docker ps -a

# View service status with health
docker ps --format "table {{.Names}}\t{{.Status}}"

# View logs (last 50 lines)
docker compose logs --tail=50 <service-name>

# Follow logs (live)
docker compose logs -f <service-name>

# Restart a service
docker restart <service-name>

# Restart all services
docker compose restart

# Stop all services
docker compose stop

# Start all services
docker compose up -d

# Full restart (stop + start)
docker compose down && docker compose up -d
```

---

## 🔍 Health Checks

### All Services Summary
```bash
docker compose ps

# Expected output shows these services HEALTHY/UP:
code-server, caddy, oauth2-proxy, postgres, redis, prometheus, 
grafana, alertmanager, jaeger, ollama (optional)
```

### Individual Service Checks
```bash
# Code-Server
curl -s http://localhost:8080 | head -c 100

# OAuth2-Proxy (health endpoint)
curl -s http://localhost:4180/health

# Prometheus
curl -s http://localhost:9090/-/healthy

# Grafana
curl -s http://localhost:3000/api/health

# PostgreSQL
docker exec postgres_prod psql -U postgres -c "SELECT 1;"

# Redis
docker exec redis_prod redis-cli ping

# AlertManager
curl -s http://localhost:9093/-/healthy
```

### System Resources
```bash
# Docker resource usage
docker stats --no-stream

# Host system resources
free -h              # Memory
df -h                # Disk space
top -b -n 1 | head   # CPU load
iostat -x 1 2        # Disk I/O

# Network connections
ss -tlnp             # Listen on ports
netstat -an | grep ESTABLISHED
```

---

## 🔐 Authentication & OAuth

### Check OAuth Configuration
```bash
# View environment variables
cat .env | grep OAUTH

# Verify cookie secret format (should be 32 hex chars)
echo $OAUTH2_PROXY_COOKIE_SECRET | wc -c

# Expected: 33 (32 chars + newline)
```

### Test OAuth Flow
```bash
# 1. Verify oauth2-proxy is running
docker ps | grep oauth2_proxy

# 2. Check health endpoint
curl -v http://localhost:4180/health

# 3. Browser test
# Visit: http://code-server.192.168.168.31.nip.io:8080
# Should redirect to Google login
# After login, should see code-server UI
```

### Troubleshoot Login Issues
```bash
# Check oauth2-proxy logs
docker compose logs -f oauth2_proxy_prod

# Look for errors like:
# - "cookie_secret must be 16, 24, or 32 bytes"
# - "failed to get OIDC provider"
# - "redirect_uri not registered"

# Verify .env is loaded
docker compose exec oauth2_proxy_prod env | grep OAUTH
```

---

## 💾 Database Operations

### PostgreSQL Access
```bash
# Interactive SQL shell
docker exec -it postgres_prod psql -U postgres

# Within psql:
\dt              # List tables
\l               # List databases
SELECT version(); # Check version

# Exit
\q
```

### Common PostgreSQL Queries
```bash
# Count code-server sessions
docker exec postgres_prod psql -U postgres -c \
  "SELECT count(*) FROM code_server_sessions;"

# Check replication status
docker exec postgres_prod psql -U postgres -c \
  "SELECT * FROM pg_stat_replication;"

# Get current WAL position
docker exec postgres_prod psql -U postgres -c \
  "SELECT pg_current_wal_lsn();"

# Full database backup
docker exec postgres_prod pg_dump -U postgres code_server > backup.sql
```

### Redis Access
```bash
# Interactive Redis shell
docker exec -it redis_prod redis-cli

# Within redis-cli:
KEYS *           # List all keys
GET <key>        # Get value
SCAN 0           # Scan keys (iterator)
INFO             # Server info
DBSIZE           # Total keys
FLUSHALL         # Clear all data (⚠️ be careful)

# Exit
EXIT
```

### Backup Management
```bash
# View backup files
ls -lah backups/

# Restore from backup
tar xzf backups/code-server-user-profile-<timestamp>.tgz -C /home/akushnir/

# Manual backup
docker compose exec -T code-server_prod tar czf /tmp/backup.tgz .local/share/code-server/
docker cp code_server_prod:/tmp/backup.tgz ./backups/manual-$(date +%Y%m%d-%H%M%S).tgz
```

---

## 📊 Monitoring & Alerts

### View Metrics
```bash
# Prometheus (web UI)
# http://192.168.168.31:9090

# Query specific metric (example - CPU)
curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' | jq .

# Query with time range (last 1 hour)
curl -s 'http://localhost:9090/api/v1/query_range?query=up&start=1m&end=now&step=30s' | jq .
```

### Check Alerts
```bash
# AlertManager (web UI)
# http://192.168.168.31:9093

# Query active alerts via API
curl -s http://localhost:9093/api/v1/alerts | jq '.data.alerts[] | {status: .status, name: .labels.alertname}'

# Silence an alert (temporarily)
curl -X POST http://localhost:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name":"alertname","value":"CodeServerUnhealthy"}],
    "duration": "1h"
  }'
```

### Grafana Dashboards
```bash
# Access Grafana
# http://192.168.168.31:3000
# Login: admin / admin123

# Common dashboards:
# 1. Code-Server Health & Performance
# 2. OAuth Authentication Metrics
# 3. PostgreSQL Database Dashboard
# 4. Redis Cache Statistics
# 5. Network I/O & Bandwidth
```

---

## 🔄 Failover & Replication

### Check Replication Status
```bash
# SSH to primary
ssh akushnir@192.168.168.31

# PostgreSQL replication lag
docker exec postgres_prod psql -U postgres -c \
  "SELECT client_addr, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

# Expected: All LSN values close (< 100 bytes difference)

# Check replica WAL receiver
ssh akushnir@192.168.168.42
docker exec postgres_replica psql -U postgres -c \
  "SELECT pg_last_wal_receive_lsn();"
```

### Manual Failover (if primary is down)
```bash
# SSH to replica
ssh akushnir@192.168.168.42

# Check replica status
docker exec postgres_replica psql -U postgres -c \
  "SELECT pg_is_in_recovery();"
# Should return 't' (in recovery/standby mode)

# Promote replica to primary
docker exec postgres_replica psql -U postgres -c \
  "SELECT pg_promote();"

# Verify promotion
docker exec postgres_replica psql -U postgres -c \
  "SELECT pg_is_in_recovery();"
# Should now return 'f' (no longer in recovery)

# Update DNS/Cloudflare to point to 192.168.168.42
# (Manual step - Cloudflare dashboard)
```

### Failback to Primary (after repair)
```bash
# 1. Fix issue on primary (192.168.168.31)
ssh akushnir@192.168.168.31

# 2. Start containers
docker compose up -d

# 3. Resync from new primary
docker exec postgres_prod pg_basebackup -h 192.168.168.42 -D /var/lib/postgresql/data -P -v -W

# 4. Start streaming replication
docker exec postgres_prod psql -U postgres -c \
  "SELECT * FROM pg_stat_replication;" # Should show connection from 192.168.168.42

# 5. Update DNS back to 192.168.168.31
```

---

## 🐛 Troubleshooting

### Service Won't Start
```bash
# Check logs
docker compose logs --tail=100 <service-name>

# Verify dependencies
# - Does postgres_prod need to be healthy first?
# - Does app need postgres to be ready?

# Manual start to see errors
docker compose up <service-name>

# Common issues:
# - Port already in use: docker ps -a | grep LISTEN
# - Out of disk space: df -h
# - Out of memory: free -h
# - File permissions: ls -la <file>
```

### High CPU/Memory Usage
```bash
# Identify process
docker stats --no-stream

# Check container processes
docker top <container-id>

# Get detailed metrics
docker inspect <container-id> | grep -E "Memory|Cpu"

# View logs (might show activity spike)
docker compose logs --tail=100 <service-name> | grep -E "ERROR|WARN|spike"

# Solution options:
# 1. Increase container memory: Edit docker-compose.yml
# 2. Optimize queries: Check PostgreSQL slow query log
# 3. Restart service: docker restart <service-name>
```

### Network Connectivity Issues
```bash
# Test DNS resolution
nslookup kushnir.cloud
nslookup code-server.192.168.168.31.nip.io

# Test network connectivity
ping 8.8.8.8                           # External
ping 192.168.168.42                    # Replica
curl http://192.168.168.42:8080        # Remote service

# Check host network
ss -tlnp                               # Listening ports
netstat -an | grep ESTABLISHED         # Active connections
netstat -an | grep TIME_WAIT           # Closing connections

# Check docker network
docker network inspect bridge
```

### OAuth Login Loop
```bash
# Check OAuth2-proxy logs
docker compose logs --tail=50 oauth2_proxy_prod

# Common causes:
# 1. CSRF token cookie not being sent (SameSite issue)
#    Fix: OAUTH2_PROXY_COOKIE_SAMESITE=none
#
# 2. Cookie secret wrong format (not 16/24/32 bytes)
#    Fix: OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -hex 16)
#
# 3. Redirect URI not registered in Google OAuth console
#    Check: Settings > OAuth > Allowed Redirect URIs
#
# 4. Client ID/Secret wrong or expired
#    Check: .env has correct values

# After fixing, restart oauth2-proxy
docker restart oauth2_proxy_prod
```

### Database Connection Errors
```bash
# Check PostgreSQL is running
docker ps | grep postgres

# Test direct connection
docker exec postgres_prod psql -U postgres -c "SELECT 1;"

# Check connection limits
docker exec postgres_prod psql -U postgres -c \
  "SELECT * FROM pg_stat_activity WHERE state = 'active';"

# Solutions:
# 1. Increase max_connections in postgresql.conf
# 2. Kill idle connections: SELECT pg_terminate_backend(pid)
# 3. Restart PostgreSQL: docker restart postgres_prod
```

---

## 📝 Common Commands Cheat Sheet

```bash
# Service Management
docker compose up -d [service]          # Start service(s)
docker compose down                     # Stop all services
docker compose ps                       # View status
docker compose logs -f [service]        # Follow logs
docker restart [service]                # Restart service

# Database Access
docker exec -it postgres_prod psql -U postgres
docker exec -it redis_prod redis-cli

# Monitoring/Debugging
docker stats                            # Resource usage
docker ps --format "..."                # Formatted output
docker inspect [container]              # Detailed info
docker top [container]                  # Running processes

# Network Testing
curl http://localhost:[port]            # Test connectivity
ping [host]                             # Test reachability
netstat -an | grep LISTEN               # Show listening ports
ss -tlnp                                # Show listening ports (newer)

# System Info
free -h                                 # Memory
df -h                                   # Disk
top -b -n 1 | head                      # CPU & processes
lsb_release -a                          # OS version
uname -r                                # Kernel version

# File Operations
tar czf backup.tgz directory/           # Create backup
tar xzf backup.tgz -C destination/      # Extract backup
find . -name "*.log" -mtime +7 -delete  # Delete old logs
```

---

## 🚨 Emergency Procedures

### If Primary (192.168.168.31) is Down
```bash
# 1. Confirm primary is unreachable
ping 192.168.168.31

# 2. Promote replica to primary
ssh akushnir@192.168.168.42
docker exec postgres_replica psql -U postgres -c "SELECT pg_promote();"

# 3. Update DNS (Cloudflare dashboard)
# Point kushnir.cloud → 192.168.168.42

# 4. Update application config
# Edit .env: DEPLOY_HOST=192.168.168.42
# Restart services: docker compose up -d

# 5. Monitor failover
# Check Prometheus: http://192.168.168.42:9090
# Check alerts fired during failover
```

### If Data is Corrupted
```bash
# 1. Identify corruption
docker exec postgres_prod psql -U postgres -c \
  "SELECT * FROM pg_catalog.pg_tables WHERE tablename = 'affected_table';"

# 2. Restore from backup
# Stop application
docker compose stop code_server

# Restore database
docker exec postgres_prod pg_restore -d code_server /backup/dump.sql

# 3. Verify data
docker exec postgres_prod psql -U postgres -c \
  "SELECT count(*) FROM affected_table;"

# 4. Restart application
docker compose up -d code_server
```

### If Disk is Full
```bash
# 1. Find what's using space
du -sh /* | sort -h

# 2. Clean up logs
docker compose logs --tail=0 > /dev/null
# OR manually delete old logs
rm -rf /var/lib/docker/containers/*/logs/*

# 3. Clean up old backups
ls -t backups/*.tgz | tail -n +4 | xargs rm

# 4. Clean Docker cache
docker system prune --volumes -f

# 5. Extend volume (if available)
# This depends on your storage setup
```

---

## 📞 Support Contacts

### Repository
- GitHub: https://github.com/kushin77/code-server
- Issues: https://github.com/kushin77/code-server/issues

### Documentation
- Deployment: [DEPLOYMENT-EPIC-950-SUMMARY-APRIL-2026.md](./DEPLOYMENT-EPIC-950-SUMMARY-APRIL-2026.md)
- Validation: [POST-DEPLOYMENT-VALIDATION-APRIL-2026.md](./POST-DEPLOYMENT-VALIDATION-APRIL-2026.md)
- Runbooks: See `/docs/runbooks/`

### Useful Links
- Prometheus: http://192.168.168.31:9090
- Grafana: http://192.168.168.31:3000
- AlertManager: http://192.168.168.31:9093
- Jaeger: http://192.168.168.31:16686
- Code-Server: http://code-server.kushnir.cloud:8080

---

## Last Updated
**Date**: April 22, 2026  
**Version**: 1.0  
**Status**: ✅ PRODUCTION READY

---

*For detailed procedures, see the full documentation in `/docs/`*
