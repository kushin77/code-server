# P0 SECURITY AUDIT REMEDIATION PLAN
# Critical fixes for April 20, 2026 audit findings

**Date**: April 24, 2026  
**Severity**: 7 CRITICAL, 33 other findings  
**Status**: Remediation Planning  

---

## Critical Issues Addressed

### #968 - Hardcoded Caddyfile LB Cookie Secret ✅ 
**Fix**: See SECURITY-FIX-968-COOKIE-SECRET.md  
**Status**: Implementation plan provided  

### #969 - oauth2-proxy + session-broker Running as Root

**Vulnerability**:  
- Docker socket mounted as root user
- Host escape path: exploit container → root access → host compromise
- Severity: CRITICAL

**Remediation**:

```yaml
# docker-compose.yml changes

oauth2-proxy:
  user: "101:101"  # oauth2 user:group (non-root)
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE
  security_opt:
    - no-new-privileges:true

session-broker:
  user: "1000:1000"  # app user:group (non-root)
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE
  security_opt:
    - no-new-privileges:true

caddy:
  user: "1001:1001"  # caddy user:group (non-root)
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE  # For port 80, 443
    - NET_RAW  # For health checks
  security_opt:
    - no-new-privileges:true
```

**Dockerfile Changes**:

```dockerfile
# For all services

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Don't run as root
USER appuser

# Verify non-root
RUN test "$(id -u)" != "0" || exit 1
```

**Testing**:

```bash
# Verify containers run as non-root
docker compose ps -q | while read cid; do
  echo "Container: $cid"
  docker inspect "$cid" --format='User: {{.Config.User}}'
done

# Expected: User: 1000:1000, 101:101, 1001:1001 (NOT 0:0)
```

---

### #971 - Redis Has No Authentication

**Vulnerability**:  
- Redis accessible without password
- Shared CODE_SERVER_PASSWORD across all sessions (credential reuse)
- Any user can access other users' data

**Remediation**:

```yaml
# redis service in docker-compose.yml

redis:
  command: |
    redis-server 
    --requirepass ${REDIS_PASSWORD}
    --maxmemory ${REDIS_MAX_MEMORY:-256mb}
    --maxmemory-policy allkeys-lru
    --save ""  # Disable disk persistence
    --appendonly no
    --protected-mode yes
  environment:
    REDIS_PASSWORD: ${REDIS_PASSWORD}
  # Network isolation
  networks:
    - net-app  # Internal only, not exposed
```

**Updated Clients**:

```yaml
# oauth2-proxy
oauth2-proxy:
  environment:
    OAUTH2_PROXY_REDIS_PASSWORD: ${REDIS_PASSWORD}

# session-broker
session-broker:
  environment:
    REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379

# code-server
code-server:
  environment:
    REDIS_AUTH: ${REDIS_PASSWORD}
```

**.env.schema.json Addition**:

```json
{
  "REDIS_PASSWORD": {
    "type": "string",
    "required": true,
    "secret": true,
    "source": "gsm",
    "length": "32",
    "format": "password",
    "description": "Redis authentication password (32+ chars, alphanumeric + symbols)",
    "production": "**FROM_GSM**",
    "rotation": "every 90 days"
  },
  "REDIS_MAX_MEMORY": {
    "type": "string",
    "default": "256mb",
    "description": "Redis max memory limit with eviction policy"
  }
}
```

**Testing**:

```bash
# Verify Redis requires password
redis-cli -h redis ping
# Expected: Error: (error) WRONGTYPE Operation against a key holding the wrong kind of value
# Or: (error) NOAUTH Authentication required

# Verify with correct password
redis-cli -h redis -a ${REDIS_PASSWORD} ping
# Expected: PONG
```

**Password Rotation**:

```bash
# Safely rotate Redis password
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 32)

# 2. Set new password in GSM
gcloud secrets versions add redis-password --data-file=- << EOF
$NEW_PASS
EOF

# 3. Update docker-compose and restart
REDIS_PASSWORD=$NEW_PASS docker compose up -d redis

# 4. Verify clients still connect
docker compose logs oauth2-proxy | grep -i connected
```

---

## Phase 2: Security Issues (P1-P2)

### #998 - Remove Hardcoded Fallback from IDE_SESSION_LB_SECRET

**Fix**:  
Change Caddyfile from:
```caddy
lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:secret734}
```

To:
```caddy
lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET}
```

**Impact**: Caddy will fail to start if variable is missing (desired security behavior)

---

### #980 - Secret Scanning for Git-Committed Secrets

**Implementation**:

```bash
# Install git-secrets
brew install git-secrets

# Configure patterns
git secrets --add 'secret[0-9]{3}'
git secrets --add --global 'api_key'
git secrets --add --global 'Bearer ey'
git secrets --add --global 'token='

# Scan repository
git secrets --scan

# Prevent commits with secrets
git secrets --install
git secrets --install -t pre-commit
git secrets --install -t pre-push
```

**GitHub Secret Scanning**:

```yaml
# .github/workflows/secret-scan.yml

name: Secret Scanning

on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: TruffleHog Scan
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD
          extra_args: --only-verified
```

---

## Remaining Audit Findings (33)

### High Priority (P1)

- **Infrastructure**: Database replication, network policies, backup strategy
- **Security**: SSL/TLS cert rotation, RBAC for Kubernetes, audit logging
- **Deployment**: Terraform state encryption, IaC drift detection

### Medium Priority (P2)

- **Operations**: Monitoring thresholds, alerting rules, runbook documentation
- **Quality**: Test coverage, E2E scenarios, performance baselines
- **Documentation**: Architecture diagrams, disaster recovery procedures

---

## Implementation Timeline

| Issue | Priority | Est. Hours | Timeline |
|-------|----------|-----------|----------|
| #968 - Cookie Secret | P0 | 2 | Immediate |
| #969 - Non-Root Containers | P0 | 3 | Today |
| #971 - Redis Auth | P0 | 2 | Today |
| #998 - Remove Fallback | P1 | 0.5 | This week |
| #980 - Secret Scanning | P1 | 1 | This week |
| Other P1 findings | P1 | 15 | 2-3 weeks |
| P2 findings | P2 | 25+ | Backlog |

---

## Acceptance Criteria

### #968 Completed
- ✅ IDE_SESSION_LB_SECRET in schema
- ✅ Secret generated and in GSM
- ✅ Caddy receives env var
- ✅ No fallback to "secret734"

### #969 Completed
- ✅ All services run as non-root
- ✅ Minimal capabilities (CAP_NET_BIND_SERVICE only)
- ✅ security_opt no-new-privileges
- ✅ Verify `docker inspect` shows non-root user

### #971 Completed
- ✅ Redis requirepass enabled
- ✅ REDIS_PASSWORD in schema
- ✅ All clients use password auth
- ✅ redis-cli -a PASSWORD works
- ✅ Connections without password fail
- ✅ Rotation policy documented

---

## Verification Commands

```bash
# Verify non-root containers
docker compose ps -q | xargs -I {} docker inspect {} --format='{{.Name}}: {{.Config.User}}'

# Verify Redis auth
docker compose exec redis redis-cli -a ${REDIS_PASSWORD} ping
# Expected: PONG

# Verify secret scanning
git secrets --scan
# Expected: No matches

# Verify SSL/TLS certificates
docker compose exec caddy openssl s_client -connect localhost:443 -showcerts < /dev/null
# Expected: Valid cert, not self-signed

# Verify health checks pass
docker compose logs --tail=20 caddy oauth2-proxy session-broker redis
# Expected: All services healthy
```

---

## Deployment Checklist

- [ ] Generate all secrets (IDE_SESSION_LB_SECRET, REDIS_PASSWORD)
- [ ] Create/update GSM secrets
- [ ] Update .env.schema.json with new variables
- [ ] Update docker-compose with non-root users, capabilities, env vars
- [ ] Update Dockerfiles to create users and validate
- [ ] Update deployment documentation
- [ ] Merge to main branch
- [ ] Deploy to staging environment
- [ ] Run all verification commands
- [ ] Deploy to production (192.168.168.31)
- [ ] Verify production logs
- [ ] Document rotation procedures

---

## Follow-up Issues

- **#967**: P0 EPIC - Complete audit findings
- **#982**: P0 EPIC - QA user and E2E testing infrastructure
- **#983**: P0 - Create qa@kushnir.cloud Google Workspace user
- **#984**: P0 - Configure QA user OAuth whitelist + GSM

---

**Next Step**: Implement fixes in order: #968 → #969 → #971 → #998 → #980

All fixes must be completed before any new feature deployments.
