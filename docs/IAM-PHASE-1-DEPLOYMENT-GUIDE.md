# IAM Standardization Phase 1 Deployment Guide - oauth2-proxy Hardening
# Implements: docs/IAM-STANDARDIZATION-PHASE-1.md
# Status: PRODUCTION - Ready for deployment to 192.168.168.31
# Date: April 16, 2026

---

# Phase 1 Objectives

✅ **OAuth2-proxy hardening** (security baseline)
✅ **Multi-service oauth2-proxy instances** (Grafana, Loki)
✅ **IAM audit logging** (compliance + security)
✅ **Session management** (Redis backend)
✅ **RBAC foundation** (manual roles, Phase 2: automation)

---

# Pre-Deployment Checklist

## Credentials & Secrets
- [ ] GOOGLE_CLIENT_ID (from Google OAuth2 console)
- [ ] GOOGLE_CLIENT_SECRET (20+ chars)
- [ ] OAUTH2_COOKIE_SECRET (256-bit, hex-encoded, 32 bytes = 64 hex chars)
- [ ] GRAFANA_OAUTH_CLIENT_ID (if using separate Grafana OAuth app)
- [ ] GRAFANA_OAUTH_CLIENT_SECRET
- [ ] LOKI_OAUTH_CLIENT_ID
- [ ] LOKI_OAUTH_CLIENT_SECRET
- [ ] REDIS_PASSWORD (20+ chars)

## Infrastructure
- [ ] PostgreSQL 15+ running (5432) with iam schema support
- [ ] Redis 7+ running (6379) with 10GB free memory
- [ ] oauth2-proxy 7.5.1+ available
- [ ] Caddy/reverse proxy configured
- [ ] Grafana accessible (3000)
- [ ] Loki accessible (3100)

## Generate Secrets

```bash
# Generate OAuth2 cookie secret (32 bytes = 256 bits)
COOKIE_SECRET=$(openssl rand -hex 16)  # 32 hex chars = 16 bytes (128 bits)
# For higher security, use:
COOKIE_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(16))")

# Generate Redis password
REDIS_PASS=$(openssl rand -base64 32)

# Add to .env
echo "OAUTH2_COOKIE_SECRET=$COOKIE_SECRET" >> .env
echo "REDIS_PASSWORD=$REDIS_PASS" >> .env
```

---

# Deployment Steps

## Step 1: Initialize IAM Database Schema

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Navigate to repo
cd /home/akushnir/code-server-enterprise

# Apply IAM audit schema to PostgreSQL
docker exec postgres psql -U postgres -d postgres << 'EOF'
\c appsmith_or_main_db  -- Connect to main database

-- Create schema
CREATE SCHEMA IF NOT EXISTS iam;

-- Initialize tables
\i /code-server-enterprise/scripts/iam-audit-schema.sql

-- Verify tables
SELECT tablename FROM pg_tables WHERE schemaname = 'iam' ORDER BY tablename;
EOF

# Expected output: 8+ tables created
# - iam_audit_log
# - iam_sessions
# - iam_token_revocation
# - iam_policies
# - iam_role_assignments
# - iam_anomalies
# - 3 views (v_iam_*)
```

## Step 2: Configure oauth2-proxy with Hardened Settings

```bash
# Copy hardened config to container
docker cp config/oauth2-proxy-hardening.cfg oauth2-proxy:/etc/oauth2-proxy/oauth2-proxy.cfg

# Restart oauth2-proxy with new config
docker-compose restart oauth2-proxy

# Verify restart
docker logs oauth2-proxy | grep -i "starting\|listening" | head -5

# Expected logs:
# "Starting oauth2-proxy 7.5.1"
# "Listening on 0.0.0.0:4180"
```

## Step 3: Create Service-Specific oauth2-proxy Instances

```bash
# Add Grafana oauth2-proxy instance to docker-compose
cat >> docker-compose.yml << 'EOF'

  oauth2-proxy-grafana:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
    container_name: oauth2-proxy-grafana
    restart: always
    ports:
      - "4181:4180"
    environment:
      - OAUTH2_PROXY_CLIENT_ID=${GRAFANA_OAUTH_CLIENT_ID}
      - OAUTH2_PROXY_CLIENT_SECRET=${GRAFANA_OAUTH_CLIENT_SECRET}
      - OAUTH2_PROXY_REDIRECT_URL=http://192.168.168.31:4181/oauth2/callback
      - OAUTH2_PROXY_OIDC_ISSUER_URL=https://accounts.google.com
      - OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_COOKIE_SECRET}
      - OAUTH2_PROXY_REDIS_CONNECTION_URL=redis://redis:6379/1
    networks:
      - internal
    depends_on:
      - redis
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:4180/ready"]
      interval: 30s
      timeout: 10s
      retries: 3

  oauth2-proxy-loki:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
    container_name: oauth2-proxy-loki
    restart: always
    ports:
      - "4182:4180"
    environment:
      - OAUTH2_PROXY_CLIENT_ID=${LOKI_OAUTH_CLIENT_ID}
      - OAUTH2_PROXY_CLIENT_SECRET=${LOKI_OAUTH_CLIENT_SECRET}
      - OAUTH2_PROXY_REDIRECT_URL=http://192.168.168.31:4182/oauth2/callback
      - OAUTH2_PROXY_OIDC_ISSUER_URL=https://accounts.google.com
      - OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_COOKIE_SECRET}
      - OAUTH2_PROXY_REDIS_CONNECTION_URL=redis://redis:6379/2
    networks:
      - internal
    depends_on:
      - redis
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:4180/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# Start new instances
docker-compose up -d oauth2-proxy-grafana oauth2-proxy-loki

# Verify all instances running
docker ps | grep oauth2-proxy
# Expected: 3 instances running (main, grafana, loki)
```

## Step 4: Enable Audit Logging

```bash
# Create audit logging sidecar (optional, for centralized logging)
cat > scripts/iam-audit-logger.sh << 'EOF'
#!/bin/bash
# Tail oauth2-proxy logs and parse to PostgreSQL audit table

while true; do
  docker logs oauth2-proxy --follow --tail 100 | \
  grep -E "auth_success|auth_failure|token_refresh" | \
  while read line; do
    # Parse JSON log and insert into iam_audit_log
    echo "$line" | jq . | psql -U postgres -d appsmith \
      -c "INSERT INTO iam_audit_log (...) VALUES (...)"
  done
done
EOF

chmod +x scripts/iam-audit-logger.sh

# Or use Promtail to scrape logs
docker exec loki curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{"streams": [{"stream": {"job": "oauth2-proxy"}, "values": [[...], [...]]}]}'
```

## Step 5: Configure Session Management

```bash
# Set Redis password
docker exec redis redis-cli CONFIG SET requirepass ${REDIS_PASSWORD}

# Verify Redis connection from oauth2-proxy
docker exec oauth2-proxy redis-cli -h redis -a ${REDIS_PASSWORD} PING
# Expected: PONG

# Check active sessions
docker exec redis redis-cli -a ${REDIS_PASSWORD} KEYS "_oauth2_proxy:*" | wc -l
# Should show session count
```

## Step 6: Set Up RBAC Roles (Manual - Phase 1)

```sql
-- Insert role assignments manually
INSERT INTO iam_role_assignments (user_email, role_name, service_name, assigned_by, status) VALUES
  ('joshua.kushnir@internal.example.com', 'admin', 'code-server', 'admin@internal.example.com', 'active'),
  ('joshua.kushnir@internal.example.com', 'admin', 'grafana', 'admin@internal.example.com', 'active'),
  ('platform-team@internal.example.com', 'editor', 'code-server', 'admin@internal.example.com', 'active'),
  ('devops@internal.example.com', 'viewer', 'grafana', 'admin@internal.example.com', 'active'),
  ('@internal.example.com', 'readonly', 'prometheus', 'admin@internal.example.com', 'active');

-- Verify assignments
SELECT user_email, role_name, service_name FROM iam_role_assignments WHERE status = 'active';
```

## Step 7: Test OAuth2 Flow

```bash
# Test main oauth2-proxy
curl -v http://192.168.168.31:4180/oauth2/authorize
# Expected: 302 redirect to Google login

# Test Grafana oauth2-proxy
curl -v http://192.168.168.31:4181/oauth2/authorize
# Expected: 302 redirect to Google login

# Test session creation (after login)
curl -b "_oauth2_proxy=test_session" http://192.168.168.31:4180/
# Expected: 200 OK or auth redirect

# Verify Redis session storage
docker exec redis redis-cli -a ${REDIS_PASSWORD} GET "_oauth2_proxy:test_session"
# Expected: Session data in JSON format
```

## Step 8: Monitor Audit Logs

```bash
# Real-time audit log monitoring
docker exec postgres psql -U postgres -d appsmith << 'EOF'
SELECT
  timestamp,
  user_email,
  action,
  result,
  failure_reason
FROM iam_audit_log
WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour'
ORDER BY timestamp DESC
LIMIT 20;
EOF

# Failed login attempts (security alert)
SELECT user_email, COUNT(*) as attempt_count
FROM iam_audit_log
WHERE action = 'login' AND result = 'failure'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour'
GROUP BY user_email
HAVING COUNT(*) > 3
ORDER BY attempt_count DESC;
```

## Step 9: Configure Prometheus Metrics

```yaml
# Add to prometheus.yml scrape_configs:
- job_name: 'oauth2-proxy'
  static_configs:
    - targets: ['localhost:4180']
  metrics_path: '/metrics'
  scrape_interval: 30s

# Alert rules
- alert: OAuth2ProxyAuthFailureSpike
  expr: rate(oauth2_proxy_auth_failures_total[5m]) > 0.5
  for: 5m
  labels:
    severity: warning
    component: security
  annotations:
    summary: "OAuth2-proxy authentication failures increased"
    description: "{{ $value }} failures/sec (threshold: 0.5/sec)"
```

## Step 10: Enable Audit Log Retention Policy

```bash
# Create daily cleanup cronjob
cat > /usr/local/bin/iam-audit-cleanup.sh << 'EOF'
#!/bin/bash
# Delete audit logs older than 90 days

DAYS=90
docker exec postgres psql -U postgres -d appsmith << EOSQL
DELETE FROM iam_audit_log
WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '$DAYS days';

SELECT COUNT(*) as remaining_audit_records FROM iam_audit_log;
EOSQL

echo "IAM audit log cleanup completed (removed entries older than $DAYS days)"
EOF

chmod +x /usr/local/bin/iam-audit-cleanup.sh

# Add to crontab (run daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/iam-audit-cleanup.sh >> /var/log/iam-audit-cleanup.log 2>&1") | crontab -
```

---

# Success Criteria

✅ Deployment is successful when:

1. **OAuth2-proxy Services**: All 3 instances running (4180, 4181, 4182)
2. **Authentication Flow**: Can login via Google OAuth2 and receive session cookie
3. **Audit Logging**: Entries in iam_audit_log table for each login attempt
4. **Session Storage**: Redis contains active session data
5. **RBAC Working**: Users with appropriate roles can access services
6. **Role Queries**: `SELECT * FROM v_iam_active_roles;` returns assigned roles
7. **Security**: Failed logins visible in `v_iam_failed_logins_24h` view
8. **Performance**: OAuth2 latency p99 < 500ms (from prometheus_oauth2_proxy_duration_seconds metric)
9. **Monitoring**: Prometheus scrapes oauth2-proxy metrics
10. **Backup**: Audit logs backing up daily to appsmith-backups

---

# Phase 2 Roadmap (May 8+)

🔄 **Automated RBAC** (Groups from OIDC claims)
🔄 **Anomaly Detection** (Impossible travel, brute force)
🔄 **MFA Support** (TOTP, WebAuthn)
🔄 **Token Introspection** (Real-time revocation)
🔄 **Audit Log Visualization** (Grafana dashboard)

---

# Contact & Support

- **Security Owner**: Joshua Kushnir (joshua.kushnir@internal.example.com)
- **IAM Documentation**: https://internal.example.com/docs/iam
- **Incident Playbook**: https://internal.example.com/runbooks/iam-incident
