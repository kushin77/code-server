# Tier 2 #184: Git Commit Proxy Implementation

**Status:** In Progress  
**Effort:** 4 hours  
**Dependencies:** #185 (Cloudflare Tunnel) ✅ COMPLETED  
**Owner:** Platform Team  
**Target Completion:** April 15, 2026

## Overview

Implement secure git proxy server that allows developers to push/pull code without direct SSH key access. Eliminates SSH private key distribution while maintaining full git workflow.

### Architecture

```
Developer Machine                    Home Server (Proxy)           GitHub
   (git push)                      (Behind Cloudflare)              |
        |                                  |                         |
        +---> HTTPS to Proxy   +---> SSH to GitHub ----+          |
              (+ CF token)     |   (with SSH key)       |          |
                               |                        +---> Pull/Push
                               | (Rate limit + Audit)   |
                               +<----- Response  <------+
```

### Security Model

1. **No SSH keys on developer machines** - Keys stay on home server only
2. **Cloudflare Access token required** - Must be authenticated to Cloudflare Access
3. **Protected branch enforcement** - Can't push directly to main/main/production
4. **Audit logging** - All pushes logged with developer email + timestamp
5. **Rate limiting** - Configurable limits per developer
6. **Timeout protection** - All operations have 30-second timeout

## Implementation Steps

### Step 1: Deploy Git Proxy Server on Home Server

**File:** `scripts/git-proxy-server.py`  
**Status:** ✅ CREATED

Features:
- FastAPI server listening on port 8001 (internal)
- Exposed via Cloudflare Tunnel on `git-proxy.dev.yourdomain.com`
- Cloudflare JWT validation on every request
- Protected branch checks (main, master, production)
- SSH key authentication to GitHub using home server keys
- Audit logging to `/var/log/git-proxy-audit.log`

Endpoints:
- `POST /git/credentials` - Get authentication status
- `POST /git/push` - Push to specific branch
- `POST /git/pull` - Pull from specific branch
- `GET /logs/audit` - View audit logs (admin only)
- `GET /health` - Health check

### Step 2: Developer Setup Script

Create setup script that developers run locally:

```bash
#!/usr/bin/env bash
# Setup git proxy access for developer machine

set -e

# 1. Install git-credential-helper
sudo cp scripts/git-credential-helper.py /usr/local/bin/git-credential-cloudflare-proxy
sudo chmod +x /usr/local/bin/git-credential-cloudflare-proxy

# 2. Install dependencies
pip3 install requests pyjwt

# 3. Configure git to use proxy
git config --global credential.helper cloudflare-proxy

# 4. Set environment variables
cat >> ~/.bashrc << 'EOF'
export GIT_PROXY_HOST="git-proxy.dev.yourdomain.com"
export GIT_PROXY_PORT="443"  # HTTPS via Cloudflare
export CLOUDFLARE_TOKEN_ENDPOINT="https://dev.yourdomain.com/oauth/token"
EOF

# 5. Test connectivity
echo "Testing proxy connection..."
curl -H "Authorization: Bearer $(cloudflared access token --hostname git-proxy.dev.yourdomain.com)" \
  https://git-proxy.dev.yourdomain.com:443/health

echo "✅ Git proxy setup complete!"
```

### Step 3: Integration with Code-Server

When developers access code-server IDE, auto-inject git proxy configuration:

```bash
# In code-server startup (phase-13-day2-bootstrap.sh)
export GIT_PROXY_HOST="git-proxy.dev.yourdomain.com"
export CF_ACCESS_TOKEN="<auto-injected-by-tunnel>"

# Configure git for this session
git config --global credential.helper cloudflare-proxy
git config --global user.email "${DEVELOPER_EMAIL}"
git config --global user.name "Code Server Dev"
```

## Configuration

### Environment Variables

```bash
GIT_PROXY_HOST=git-proxy.dev.yourdomain.com        # Proxy endpoint
GIT_PROXY_PORT=443                                  # HTTPS (via Cloudflare)
CLOUDFLARE_DOMAIN=dev.yourdomain.com               # For token validation
CLOUDFLARE_PUBLIC_KEY=<JWK-set-from-dashboard>     # JWT verification
SSH_KEY_PATH=~/.ssh/id_rsa                         # Home server SSH key
GIT_REPO_BASE=~/projects                           # Repo storage location
```

### Protected Branches

By default:
- `main` ❌ Cannot push directly - requires PR
- `master` ❌ Cannot push directly - requires PR
- `production` ❌ Cannot push directly - requires PR
- All others ✅ Can push directly

## Testing

### Test 1: Verify Proxy Health

```bash
CF_TOKEN=$(cloudflared access token --hostname git-proxy.dev.yourdomain.com)
curl -H "Authorization: Bearer ${CF_TOKEN}" \
  https://git-proxy.dev.yourdomain.com/health

# Expected: {"status":"healthy","service":"git-credential-proxy"}
```

### Test 2: Verify Push Protection

```bash
cd ~/projects/code-server

# Try to push to main (should fail)
git checkout main
git push origin main  # ❌ Should be rejected: "Push to main requires PR review"

# Try to push to feature branch (should succeed)
git checkout -b feature/test-proxy
git commit --allow-empty -m "test: proxy communication"
git push origin feature/test-proxy  # ✅ Should succeed
```

### Test 3: Verify Audit Logging

```bash
# Check audit logs on home server
ssh -i ~/.ssh/home-server-key user@192.168.168.31
tail -f /var/log/git-proxy-audit.log

# Expected entries:
# [INFO] Credential request: get for github.com from dev@company.com
# [INFO] Push successful: code-server:feature/test-proxy from dev@company.com
```

### Test 4: Verify Branch Protection Enforcement

```bash
# Attempt to push to main via proxy
git push origin main

# Expected error:
# ❌ Push to main requires PR review. Please use a feature branch.
```

## Deployment

### Phase 1: Home Server Deployment (2 hours)

**Steps:**
1. Copy `git-proxy-server.py` to home server
2. Install dependencies: `pip3 install fastapi uvicorn pyjwt cloudflare`
3. Create systemd service:

```ini
[Unit]
Description=Git Credential Proxy Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=git-proxy
ExecStart=/usr/bin/python3 /opt/git-proxy/git-proxy-server.py
Restart=on-failure
RestartSec=10

Environment="CLOUDFLARE_DOMAIN=dev.yourdomain.com"
Environment="SSH_KEY_PATH=/home/git-proxy/.ssh/id_rsa"
Environment="GIT_REPO_BASE=/home/git-proxy/projects"

[Install]
WantedBy=multi-user.target
```

4. Enable via Cloudflare Tunnel in `Caddyfile`:

```caddyfile
git-proxy.dev.yourdomain.com {
    reverse_proxy localhost:8001
    
    # Rate limiting: 100 req/min per IP
    rate_limit {
        zones http://localhost:8001
        100 requests per minute
    }
}
```

5. Test connectivity from developer machine

**Verification:**
- Service running: `systemctl status git-proxy-server`
- Logs: `journalctl -u git-proxy-server -f`
- Health: `curl https://git-proxy.dev.yourdomain.com/health`

### Phase 2: Developer Onboarding (1.5 hours)

**For Each Developer:**
1. Run setup script locally
2. Verify connectivity with health check
3. Test push to feature branch
4. Confirm audit log entry appears

**Documentation:**
- Developer setup guide (README in `scripts/`)
- Troubleshooting guide
- FAQ

### Phase 3: Rate Limiting + Audit Analytics (0.5 hours)

**Monitoring:**
- Track pushes per developer per day
- Alert on unusual activity (>100 pushes/day, protected branch attempts)
- Generate weekly report: who pushed what, when

**Audit Storage:**
- Move logs to `git-proxy-audit.db` (SQLite)
- Query: `SELECT * FROM audit_log WHERE username='dev@company.com' AND timestamp > now() - interval '7 days'`

## Rollback Plan

If proxy fails:
1. Disable via Cloudflare: Comment out `git-proxy.dev.yourdomain.com` in `Caddyfile`
2. Developers can revert to direct SSH: `git config --global --unset credential.helper`
3. Restore direct SSH keys to developer machines (temporary, not recommended for production)

## Success Metrics

✅ **Completion Criteria:**
- [x] Git proxy server deployed and running on home server
- [x] Cloudflare integration verified (JWT validation working)
- [x] Push to protected branches blocked (tested)
- [ ] At least 3 developers successfully using proxy
- [ ] Zero failed git operations in prod for 24 hours
- [ ] Audit logs automatically generated for all operations

## Post-Completion Tasks

1. **Tier 2 #187 (Read-Only IDE Access)** - Depends on this proxy being stable
2. **Tier 2 #186 (Developer Lifecycle)** - Depends on audit logging
3. **Tier 2 #219 (Operations Stack)** - Depends on all enabled features

## Related Documents

- [ADR-001: Cloudflare Tunnel Architecture](../ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md)
- [PHASE-13 Day 2 Execution](../PHASE-13-DAY2-EXECUTION-RUNBOOK.md)
- [Developer Onboarding](../DEV_ONBOARDING.md)
