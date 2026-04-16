# Appsmith Portal Deployment Guide - Phase 1 Implementation
# Implements: docs/ADR-PORTAL-ARCHITECTURE.md  
# Status: PRODUCTION - Ready for deployment to 192.168.168.31
# Date: April 16, 2026

# Pre-Deployment Checklist
## Infrastructure
- [ ] PostgreSQL 15+ running (5432)
- [ ] Redis 7+ running (6379)
- [ ] oauth2-proxy 7.5+ running (4180)
- [ ] Disk space: 10GB free on /var/lib/docker/volumes/
- [ ] Memory: 2GB free on host (Appsmith uses 256MB, some headroom)
- [ ] Network: Ensure DNS/nip.io resolution works

## Credentials & Configuration
- [ ] Generate APPSMITH_ENCRYPTION_SALT (256-bit hex): `openssl rand -hex 16`
- [ ] Generate APPSMITH_ENCRYPTION_PASSWORD (16+ chars, alphanumeric+symbols)
- [ ] Create APPSMITH_DB_PASSWORD (20+ chars, no special chars that need escaping in URI)
- [ ] Obtain GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET from OAuth2 provider
- [ ] Prepare SMTP credentials (if using email notifications)
- [ ] Have ALLOWED_DOMAINS list ready (email domains for oauth2-proxy)

## Network & DNS
- [ ] Reserve port 8443 (HTTP) and 8444 (HTTPS) on 192.168.168.31
- [ ] DNS setup: appsmith.192.168.168.31.nip.io → 192.168.168.31
- [ ] oauth2-proxy redirect: appsmith callback → oauth2-proxy upstream

---

# Deployment Steps

## Step 1: Prepare Environment Variables

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Navigate to code-server repo
cd /home/akushnir/code-server-enterprise

# Create .env.appsmith file
cat > .env.appsmith << 'EOF'
# Database Credentials
APPSMITH_DB_PASSWORD=<GENERATED_PASSWORD_20_CHARS>
POSTGRES_PASSWORD=<EXISTING_POSTGRES_PASSWORD>

# Encryption
APPSMITH_ENCRYPTION_SALT=<GENERATED_HEX_32_CHARS>
APPSMITH_ENCRYPTION_PASSWORD=<GENERATED_ALPHANUMERIC_16_CHARS>

# OAuth2 Integration
GOOGLE_CLIENT_ID=<FROM_OAUTH2_PROVIDER>
GOOGLE_CLIENT_SECRET=<FROM_OAUTH2_PROVIDER>
ALLOWED_DOMAINS=internal.example.com,company.com

# SMTP (optional, for email notifications)
APPSMITH_MAIL_HOST=mail.internal.example.com
APPSMITH_MAIL_PORT=587
APPSMITH_MAIL_FROM=appsmith@internal.example.com
APPSMITH_MAIL_USERNAME=appsmith
APPSMITH_MAIL_PASSWORD=<GENERATED_PASSWORD>
EOF

# Secure the file
chmod 600 .env.appsmith
```

## Step 2: Initialize Appsmith Database

```bash
# Pull Appsmith image
docker pull appsmith/appsmith:v1.1.54

# Initialize database
docker-compose -f docker-compose.appsmith.yml --profile init up appsmith-init

# Verify initialization
docker exec postgres psql -U postgres -d appsmith -c "\dt" | head -20

# Expected output: Should show postgres tables if Appsmith schema created
```

## Step 3: Start Appsmith Service

```bash
# Start Appsmith container
docker-compose -f docker-compose.appsmith.yml up -d appsmith

# Wait for startup (120s health check grace period)
sleep 120

# Verify service health
docker ps | grep appsmith
docker logs appsmith | tail -20

# Expected logs:
# "Server started on port 80"
# "Connected to PostgreSQL database"
# "Redis connection established"
```

## Step 4: Configure oauth2-proxy Integration

```bash
# Update oauth2-proxy configuration to add Appsmith upstream

# Edit oauth2-proxy config
cat >> /path/to/oauth2-proxy.cfg << 'EOF'

# Appsmith Upstream Service
upstream-app-session-cookie-name = "_appsmith_session"
cookie-domain = "192.168.168.31"

# Appsmith-specific route
set-xauthrequest = true
skip-auth-routes = [
  "/health",
  "/api/v1/websocket",
  "/api/v1/pages/*/view"
]
EOF

# Reload oauth2-proxy
docker-compose restart oauth2-proxy

# Test oauth2-proxy → Appsmith routing
curl -I http://192.168.168.31:4180/Appsmith
# Expected: 302 redirect to login or 200 OK (depending on session)
```

## Step 5: Initial Appsmith Setup

```bash
# Access Appsmith UI
# Use browser: http://appsmith.192.168.168.31.nip.io:8443
# Or SSH tunnel:
ssh -L 8443:localhost:8443 akushnir@192.168.168.31

# In browser:
# 1. Create admin account (email + password)
# 2. Create workspace "Code Server Enterprise"
# 3. Create first application "Service Catalog"
# 4. Connect PostgreSQL datasource (postgres:5432, appsmith db)
# 5. Create initial dashboard showing:
#    - Services from portal_config
#    - Prometheus metrics (via REST API)
#    - Team directory (LDAP query if configured)
```

## Step 6: Create Portal Applications

### Application 1: Service Catalog

```sql
-- PostgreSQL Query in Appsmith
SELECT
    service_name,
    description,
    owner_team,
    contact_email,
    repository_url,
    health_check_url,
    tags,
    metadata ->> 'version' as version,
    CASE
        WHEN health_check_url IS NOT NULL THEN 'Healthy'
        ELSE 'Unknown'
    END as status
FROM public.service_catalog
ORDER BY service_name;
```

Display in Appsmith:
- [ ] Table view: Service name, description, owner, status
- [ ] Detail modal: Full service details, links, metadata
- [ ] Search/filter: By name, owner, tags
- [ ] Action buttons: View docs, open repo, health check link

### Application 2: Infrastructure Dashboard

```
- Connect to Prometheus (REST endpoint: http://prometheus:9090)
- Queries:
  - up{} (service health)
  - node_memory_MemAvailable_bytes (memory usage)
  - rate(container_cpu_usage_seconds_total[5m]) (CPU)
  - increase(error_fingerprint_count[1h]) (error rate)

- Visualizations:
  - Gauge: Overall health % (services up / total services)
  - Time series: Memory & CPU trends
  - Table: Service status & uptime
  - Heatmap: Error rate by service
```

### Application 3: Runbook/Operations

```
- Embedded documentation:
  - P0/P1 incident playbooks
  - Deployment procedures
  - Rollback guides
  - Disaster recovery procedures

- Integration with:
  - Slack notifications (via webhook action)
  - PagerDuty escalation (REST API)
  - Logging system (Loki queries for context)
```

### Application 4: Team Directory

```
- LDAP integration (if available):
  - Fetch team roster
  - On-call schedules
  - Contact information

- Fallback: Manual team table in PostgreSQL
```

## Step 7: Configure Backups

```bash
# Daily backup script
cat > /usr/local/bin/appsmith-backup.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/var/backups/appsmith"
mkdir -p $BACKUP_DIR

# Backup PostgreSQL appsmith database
docker exec postgres pg_dump \
    -U appsmith \
    -d appsmith \
    | gzip > $BACKUP_DIR/appsmith-db-$(date +%Y%m%d-%H%M%S).sql.gz

# Backup Appsmith volumes
docker run --rm \
    -v appsmith-data:/appsmith-data \
    -v $BACKUP_DIR:/backup \
    alpine tar czf /backup/appsmith-volume-$(date +%Y%m%d-%H%M%S).tar.gz \
    -C /appsmith-data .

# Cleanup old backups (keep last 30 days)
find $BACKUP_DIR -mtime +30 -delete

echo "Appsmith backup completed: $(ls -lh $BACKUP_DIR | tail -5)"
EOF

chmod +x /usr/local/bin/appsmith-backup.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/appsmith-backup.sh") | crontab -
```

## Step 8: Configure Monitoring & Alerts

```yaml
# Prometheus alert rule for Appsmith
- alert: AppsmithDown
  expr: up{job="appsmith"} == 0
  for: 5m
  labels:
    severity: critical
    component: portal
  annotations:
    summary: "Appsmith service is down"
    description: "Appsmith portal at {{ instance }} has been down for 5 minutes"

# Add Appsmith health check to Prometheus scrape config
- job_name: 'appsmith'
  static_configs:
    - targets: ['localhost:8443']
  metrics_path: '/health'
  scrape_interval: 30s
```

## Step 9: Security Hardening

```bash
# 1. Database security
docker exec postgres psql -U postgres -d appsmith << 'EOF'
REVOKE ALL PRIVILEGES ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO appsmith;
EOF

# 2. Network security: Restrict access to Appsmith only from oauth2-proxy
docker exec appsmith iptables -I INPUT -i docker0 -p tcp --dport 80 \
    ! -s $(docker inspect -f '{{.NetworkSettings.Networks.internal.IPAddress}}' oauth2-proxy) \
    -j DROP

# 3. SSL/TLS: Use oauth2-proxy's TLS termination, or:
# Generate self-signed cert (for testing)
openssl req -x509 -newkey rsa:2048 -keyout appsmith-key.pem -out appsmith-cert.pem -days 365 -nodes

# 4. Disable default credentials (set strong admin password)
# 5. Enable audit logging (already configured in portal_audit_log table)
# 6. Restrict datasource connections (no direct internet access)
```

## Step 10: Post-Deployment Verification

```bash
# Health check endpoints
curl -s http://192.168.168.31:8443/health | jq .
curl -s http://192.168.168.31:8443/api/v1/usage | head -20

# Database connectivity
docker exec postgres psql -U appsmith -d appsmith -c \
    "SELECT COUNT(*) FROM public.service_catalog;"

# Redis session store
docker exec redis redis-cli KEYS "sess:*" | wc -l

# OAuth2-proxy integration
curl -I -H "Cookie: _oauth2_proxy=test" http://192.168.168.31:4180/Appsmith

# Check logs for errors
docker logs appsmith | grep -i error | head -5
docker logs oauth2-proxy | grep -i appsmith | head -5
```

## Rollback Procedure

If deployment fails:

```bash
# 1. Stop Appsmith
docker-compose -f docker-compose.appsmith.yml down

# 2. Restore database from backup
docker exec postgres psql -U postgres << 'EOF'
DROP DATABASE appsmith;
EOF
gunzip < /var/backups/appsmith/appsmith-db-YYYYMMDD-HHMMSS.sql.gz | \
    docker exec -i postgres psql -U postgres

# 3. Restore volumes
docker run --rm \
    -v appsmith-data:/appsmith-data \
    -v /var/backups/appsmith:/backup \
    alpine tar xzf /backup/appsmith-volume-YYYYMMDD-HHMMSS.tar.gz \
    -C /appsmith-data

# 4. Start Appsmith again
docker-compose -f docker-compose.appsmith.yml up -d appsmith

# 5. Verify
docker ps | grep appsmith
docker logs appsmith | tail -20
```

---

# Success Criteria

✅ Deployment is successful when:

1. **Service Health**: `docker ps` shows appsmith container running
2. **Database**: `docker exec postgres psql -U appsmith -d appsmith -c "SELECT COUNT(*) FROM service_catalog;" returns > 0`
3. **Network**: `curl -I http://192.168.168.31:8443/health` returns 200 OK
4. **Authentication**: Accessing Appsmith redirects through oauth2-proxy login
5. **Portal Functions**:
   - Service catalog loads and displays services
   - Dashboard shows real-time infrastructure metrics
   - Runbooks render properly
   - Team directory populates
6. **Backups**: Backup script runs daily and creates compressed archives
7. **Monitoring**: Prometheus scrapes Appsmith metrics, Grafana dashboard displays health
8. **Logs**: No ERROR-level logs in appsmith container, only INFO/WARN
9. **Performance**: Portal loads in <2 seconds (p95 latency)
10. **Failover Ready**: Can restore from backup in <10 minutes

---

# Troubleshooting

## Appsmith fails to start (exit code 1)
- Check: `docker logs appsmith | tail -50`
- Common: Database password with special characters in JDBC URL
- Fix: Use URL-encoded password or change password to alphanumeric only

## OAuth2-proxy integration not working
- Check: oauth2-proxy logs for "Appsmith" or routing errors
- Check: Cookie domain settings match 192.168.168.31
- Fix: Clear browser cookies, restart oauth2-proxy

## PostgreSQL connection timeout
- Check: PostgreSQL running: `docker ps | grep postgres`
- Check: Firewall rules: `docker exec appsmith curl -v postgres:5432`
- Check: PostgreSQL log: `docker logs postgres | grep -i connection`
- Fix: Verify APPSMITH_DB_URL is correct, restart PostgreSQL

## Out of memory
- Check: `docker stats appsmith`
- If using >256MB: Increase heap size or reduce plugins
- Current config: `-Xms128m -Xmx256m` (can adjust in docker-compose.yml)

## Dashboard queries return empty results
- Check: PostgreSQL service_catalog table: `docker exec postgres psql -U appsmith -d appsmith -c "SELECT COUNT(*) FROM service_catalog;"`
- Check: Prometheus connectivity: `curl -I http://192.168.168.31:9090/-/healthy`
- Fix: Re-run appsmith-init-db.sql if tables missing

---

# Contact & Support

- **Portal Owner**: Joshua Kushnir (joshua.kushnir@internal.example.com)
- **Platform Team**: platform@internal.example.com
- **Documentation**: https://internal.example.com/docs/appsmith-portal
- **Incident Runbook**: https://internal.example.com/runbooks/portal-incident
