# Git Commit Proxy - Issue #184

## Overview

**Objective**: Enable developers to push/pull Git commits without ever accessing SSH keys.

**Problem**: Developers need Git functionality but must NOT have access to:
- SSH keys (`~/.ssh/id_rsa`)
- GitHub credentials  
- Protected branch direct access

**Solution**: All git operations are routed through an authenticated proxy server running on the home server.

---

## Architecture

```
Developer's IDE Terminal
    ↓
git push origin feature
    ↓
Git needs credentials
calls credential helper
    ↓
git-credential-cloudflare-proxy (bash script, dev machine)
    ↓
HTTPS request to proxy.dev.example.com/api/credentials
    ↓
Cloudflare Tunnel (secure, encrypted)
    ↓
Git Proxy Server (Python/FastAPI, home server)
    ├─ Validates Cloudflare Access token
    ├─ Checks rate limits
    ├─ Uses home server's SSH key (never exposed)
    ├─ Performs git operation
    ├─ Logs operation for audit
    └─ Returns temporary credentials
    ↓
Developer's IDE gets credentials
    ↓
git push completes successfully
```

### Security Properties

✓ **SSH keys never leave the home server**
- SSH key stored locally at `/home/developer/.ssh/id_rsa`
- Not accessible via network
- Only read by git-proxy-server process

✓ **Developer never sees SSH keys**
- Credentials returned are temporary tokens
- Tokens expire after use
- Not stored on developer's machine

✓ **Each operation audited**
- Developer identity tracked (from Cloudflare Access)
- Operation logged (push/pull/clone)
- Repository and branch tracked
- Timestamp recorded

✓ **HTTPS transport**
- Encrypted in transit
- Cloudflare Tunnel encryption layer
- No plaintext credentials

✓ **Authentication required**
- Cloudflare Access JWT validation
- Token expiry enforcement
- Session tracking

---

## Components

### 1. Client-Side Credential Helper

**File**: `scripts/git-credential-cloudflare-proxy`

**Language**: Bash script

**Installation**:
```bash
sudo cp scripts/git-credential-cloudflare-proxy /usr/local/bin/
sudo chmod 755 /usr/local/bin/git-credential-cloudflare-proxy

# Configure git to use this helper
git config --global credential.helper cloudflare-proxy
```

**How it works**:
1. Git's credential handler calls this script
2. Script reads git's credential format from stdin
3. Script calls home server proxy via HTTPS
4. Passes Cloudflare Access token in Authorization header
5. Proxy responds with temporary credentials
6. Credentials are cached locally (1-hour TTL)
7. Script outputs credentials in git format
8. Git uses them to authenticate

**Operations**:
- `get`: Retrieve credentials for a git host
- `store`: Record successful authentication
- `erase`: Clear cached credentials

**Caching**:
- Cache directory: `/tmp/dev-git-creds-${USER}-${SESSION_ID}`
- TTL: 1 hour (configurable)
- Cleared on session logout
- Indexed by URL hash (not plaintext)

### 2. Server-Side Proxy Server

**File**: `services/git-proxy-server.py`

**Language**: Python (FastAPI)

**Dependencies**:
```bash
pip install fastapi uvicorn pydantic PyJWT
```

**Installation Steps**:

1. Create user and directories:
```bash
useradd -r -s /bin/false -d /srv/git-proxy git-proxy
mkdir -p /etc/git-proxy /var/log/git-proxy /srv/git-proxy
chown git-proxy:git-proxy /var/log/git-proxy
```

2. Copy service files:
```bash
cp services/git-proxy-server.py /srv/git-proxy/
cp config/git-proxy/config.env.template /etc/git-proxy/config.env
cp config/systemd/git-proxy.service /etc/systemd/system/
```

3. Configure:
```bash
# Edit configuration
nano /etc/git-proxy/config.env

# Generate SSL certificate
openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/git-proxy/ssl.key \
  -out /etc/git-proxy/ssl.crt \
  -days 365 -nodes

chmod 600 /etc/git-proxy/ssl.*
```

4. Enable service:
```bash
systemctl daemon-reload
systemctl enable git-proxy
systemctl start git-proxy
systemctl status git-proxy
```

**Endpoints**:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/api/credentials` | POST | Get temporary credentials |
| `/api/git-operation` | POST | Execute git operation |

**Request Format - Credentials**:
```json
{
  "protocol": "https",
  "host": "github.com",
  "username": "developer",
  "password": "current_password"
}
```

**Response Format - Credentials**:
```json
{
  "protocol": "https",
  "host": "github.com",
  "username": "git",
  "password": "temp_token_8f2d9e..."
}
```

**Request Format - Git Operation**:
```json
{
  "operation": "push",
  "repo": "code-server",
  "branch": "feature-x"
}
```

**Response Format**:
```json
{
  "status": "success",
  "message": "Operation push completed",
  "result": {
    "operation": "push",
    "repo": "code-server",
    "branch": "feature-x",
    "output": "..."
  }
}
```

**Security Features**:
- Cloudflare Access JWT validation
- Rate limiting (default 30 requests/min per developer)
- Protected branch enforcement (no push to main/master without PR)
- Audit logging of all operations
- Request timeout enforcement (30s default)

---

## Workflow

### Scenario: Developer Pushes Code

1. **Developer's Terminal**:
```bash
cd /home/developer/repos/code-server
git push origin feature-x
```

2. **Git Needs Authentication**:
- Git calls: `git-credential-cloudflare-proxy get`
- Input: protocol=https, host=github.com

3. **Credential Helper (on dev machine)**:
- Reads stdin (protocol, host)
- Checks cache (60-min TTL)
- If not cached, calls proxy
- Headers: Authorization: Bearer {cloudflare_token}
- Proxy URL: https://git-proxy.dev.example.com/api/credentials

4. **Proxy Server (on home server)**:
- Validates Cloudflare Access JWT
- Checks rate limits (30 req/min)
- Loads SSH key: `/home/developer/.ssh/id_rsa`
- Generates temp token (valid 1 hour)
- Logs operation: developer_id=alice, operation=credential_request, host=github.com
- Returns: username=git, password=temp_8f2d9e...

5. **Git Completes**:
- Uses temporary token
- Authenticates to GitHub
- Pushes commits
- Success!

---

## Configuration

### Environment Variables (in `/etc/git-proxy/config.env`):

```bash
# Server
GIT_PROXY_HOST=127.0.0.1
GIT_PROXY_PORT=8443

# SSH Key
SSH_KEY_PATH=/home/developer/.ssh/id_rsa

# Repositories
GIT_REPOS_PATH=/home/developer/repos

# Cloudflare Access
CLOUDFLARE_ACCOUNT_ID=...
CLOUDFLARE_AUTH_DOMAIN=team.cloudflareaccess.com
CLOUDFLARE_APP_ID=...

# Security
MAX_REQUESTS_PER_MINUTE=30
PROTECTED_BRANCHES=main,master,develop
```

---

## Monitoring & Debugging

### Start service:
```bash
systemctl start git-proxy
```

### Check status:
```bash
systemctl status git-proxy
journalctl -u git-proxy -f
```

### View audit logs:
```bash
tail -f /var/log/git-proxy/audit.log
```

### Test connectivity:
```bash
curl -k https://git-proxy.dev.example.com/health
```

### Check rate limiting:
```bash
grep "Rate limit" /var/log/git-proxy/git-proxy.log
```

---

## Limitations & Considerations

### ⏱️ Performance
- Each push/pull goes through proxy (adds 50-200ms latency)
- Not ideal for low-bandwidth connections
- Mitigated by credential caching (1 hour)

### 🔗 Availability
- Depends on Cloudflare Tunnel being active
- Depends on home server being online
- Without proxy, developers can't git push

### 🔐 SSH Key Security
- SSH key must be protected on home server
- Should be read-only by git-proxy user
- Should NOT have passphrase (auto-start service)
- Consider: Use SSH agent instead of direct key file

### 📝 Audit Trail
- All operations logged with developer identity
- Logs not encrypted (consider encryption at rest)
- No deletion of audit logs (retention policy needed)

---

## Integration with Other Components

### With Cloudflare Tunnel (Issue #185):
- Git proxy runs HTTPS behind Cloudflare Tunnel
- Tunnel provides encrypted ingress
- Cloudflare Access validates JWT tokens

### With Read-Only IDE (Issue #187):
- IDE prevents file downloads
- Git proxy prevents SSH access
- Combined: Developers can only view/edit via IDE

### With Audit Logging (Issue #183):
- All git operations logged
- Integrated with security audit trail
- Compliance-ready logging

---

## Testing

### Unit Tests
```bash
pytest services/tests/test-git-proxy-server.py
```

### Integration Tests
```bash
# Test credential request
curl -k -X POST https://localhost:8443/api/credentials \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"protocol":"https","host":"github.com"}'

# Test git operation
curl -k -X POST https://localhost:8443/api/git-operation \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"status","repo":"code-server"}'
```

### End-to-End Test
```bash
# On dev machine
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes
git push origin new-branch  # Should succeed via proxy
```

---

## Future Enhancements

1. **SSH Agent Support**: Use SSH agent instead of direct SSH key file
2. **GitHub App Integration**: Temporary GitHub App tokens instead of PAT
3. **Audit Encryption**: Encrypt audit logs at rest
4. **Rate Limit Tuning**: Per-developer adaptive limits
5. **Operation Caching**: Cache successful git operations
6. **Metrics Export**: Prometheus metrics endpoint
7. **Multi-Region**: Proxy federation across regions
8. **Zero-Knowledge Proof**: PZK for operation verification

---

## See Also

- Issue #185: Cloudflare Tunnel Setup
- Issue #187: Read-Only IDE Access Control
- Issue #183: Audit Logging & Compliance
- Issue #189: Lean On-Premises Remote Developer Access System (EPIC)

---

**Status**: Implementation complete and documented  
**Last Updated**: April 13, 2026  
**Owner**: Platform Engineering Team
