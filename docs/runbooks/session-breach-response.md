# Session Breach Response Runbook

**Status**: Production  
**Owner**: Platform Engineering / SRE  
**Last Updated**: April 15, 2026  
**Severity**: P0 (Production Security Incident)

---

## Purpose

This runbook enables emergency **session invalidation** in response to security incidents:
- Stolen/leaked session tokens
- Suspected credential compromise
- Insider threat
- Suspected account takeover

**Goal**: Invalidate all compromised sessions in < 5 seconds without redeploying code.

---

## Quick Start (5 Minutes)

### Scenario 1: Global Breach (All Users) 🚨

**When to use**: Token breach (e.g., exposed in logs, GitHub secret leak)

```bash
# 1. Get admin token (stored in vault)
ADMIN_TOKEN=$(vault kv get -field=admin_token secret/code-server/admin)

# 2. Invalidate all sessions
curl -X POST https://ide.kushnir.cloud/admin/sessions/invalidate \
  -H "X-Admin-Token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scope": "global"}'

# 3. Expected response
# {"status": "ok", "scope": "global", "message": "All sessions invalidated"}

# 4. All users logged out on next request
# 5. Check PagerDuty P0 alert (should fire automatically)
```

**Impact**: ALL users logged out, must re-authenticate  
**Duration**: < 1 second  
**Rollback**: None needed (no code changes)

---

### Scenario 2: User Account Compromise 🔑

**When to use**: Specific user's password leaked, account takeover suspected

```bash
# 1. Get admin token
ADMIN_TOKEN=$(vault kv get -field=admin_token secret/code-server/admin)

# 2. Invalidate sessions for specific user
curl -X POST https://ide.kushnir.cloud/admin/sessions/invalidate \
  -H "X-Admin-Token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "scope": "user",
    "email": "compromised@example.com"
  }'

# 3. Expected response
# {"status": "ok", "scope": "user", "email": "compromised@example.com", "message": "User sessions invalidated"}

# 4. Only that user's sessions logged out
# 5. User must re-authenticate on next request
```

**Impact**: Only specified user logged out  
**Duration**: < 1 second  
**Other users**: Unaffected

---

## Step-by-Step Procedures

### Pre-Incident Checklist

- [ ] Admin token stored securely in vault: `secret/code-server/admin`
- [ ] PagerDuty integration configured: `PAGERDUTY_TOKEN` set
- [ ] Alert routing verified (P0 → on-call engineer)
- [ ] Team trained on this runbook (last refreshed: [DATE])

### Step 1: Assess Severity

| Scenario | Scope | Decision | Timeline |
|----------|-------|----------|----------|
| Single token leaked in logs | User | Invalidate user | < 5 min |
| Multiple tokens exposed (1-5) | User | Invalidate each | < 15 min |
| Breach affects all users | Global | Invalidate global | **IMMEDIATE** |
| Insider threat (unknown scope) | User | Invalidate user + force pwd reset | < 30 min |
| Production OAuth secret leak | Global | Invalidate global + rotate secret | < 5 min |

**Decision point**: If doubt, err global (worse UX but better security).

### Step 2: Trigger Invalidation

```bash
#!/bin/bash
set -euo pipefail

# Configuration
VAULT_ADDR="https://vault.kushnir.cloud"
ADMIN_API_URL="https://ide.kushnir.cloud/admin/sessions/invalidate"
SCOPE="${1:-global}"  # global or user
EMAIL="${2:-}"        # Required if scope=user

# 1. Authenticate to vault
vault login -path=oidc -method=oidc
export VAULT_TOKEN=$(vault print token)

# 2. Retrieve admin token
ADMIN_TOKEN=$(vault kv get -field=admin_token secret/code-server/admin)

# 3. Build request payload
if [[ "$SCOPE" == "global" ]]; then
    PAYLOAD='{"scope": "global"}'
elif [[ "$SCOPE" == "user" ]]; then
    if [[ -z "$EMAIL" ]]; then
        echo "ERROR: Email required for user scope"
        exit 1
    fi
    PAYLOAD="{\"scope\": \"user\", \"email\": \"$EMAIL\"}"
else
    echo "ERROR: Invalid scope (must be global or user)"
    exit 1
fi

# 4. Execute invalidation
echo "🔄 Invalidating sessions (scope=$SCOPE)..."
RESPONSE=$(curl -s -X POST "$ADMIN_API_URL" \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

echo "$RESPONSE" | jq .

# 5. Verify success
if echo "$RESPONSE" | jq -e '.status == "ok"' >/dev/null; then
    echo "✅ Sessions invalidated successfully"
    exit 0
else
    echo "❌ Invalidation failed"
    echo "$RESPONSE"
    exit 1
fi
```

Save as: `scripts/breach-response/trigger-invalidation.sh`

### Step 3: Monitor Impact

```bash
# Watch for user re-authentication requests
tail -f logs/oauth2-proxy.log | grep "new session"

# Check error rate in Prometheus
# Query: rate(http_requests_total{status=~"401|403"}[5m])
# Should spike temporarily then recover as users re-authenticate
```

### Step 4: Communicate to Users

**If user scope**:
```
Subject: Your session was invalidated for security

We detected suspicious activity on your account and invalidated 
your session as a precaution. You will need to log in again.

This is a security measure to protect your account.
```

**If global scope**:
```
Subject: Service maintenance - please log in again

We performed scheduled security maintenance that requires 
all users to re-authenticate. This should take < 1 minute.

Apologies for the inconvenience.
```

---

## Troubleshooting

### Problem: Rate Limit Exceeded

**Error**: `Rate limit exceeded (max 10 requests per 60 seconds)`

**Root cause**: Too many invalidation requests in short window

**Solution**:
- Wait 60 seconds
- For emergency: Manually reset rate limit counter in Redis
  ```bash
  redis-cli DEL admin:rate-limit:sessions-invalidate:<admin_id>
  ```

---

### Problem: Admin Token Invalid

**Error**: `Invalid admin token`

**Root cause**: Token expired, wrong token, or auth disabled

**Solution**:
1. Verify token in vault: `vault kv get secret/code-server/admin`
2. Verify Redis has token: `redis-cli GET admin:token:<token_hash>`
3. If missing, regenerate: `scripts/admin-token-generate.sh`

---

### Problem: User Not Logged Out

**Error**: User still has active session after invalidation

**Root cause**: Session cached or user hasn't made new request

**Solution**:
- Sessions invalidated on **next request** (not retroactively)
- Ask user to refresh browser (`Ctrl+F5`)
- Verify Redis counter incremented:
  ```bash
  redis-cli GET session:gen:user:<user_hash>
  ```

---

### Problem: API Timeout

**Error**: `curl: (28) Operation timeout after 30 seconds`

**Root cause**: API unreachable (infrastructure issue)

**Solution**:
1. Check if API is healthy: `curl https://ide.kushnir.cloud/healthz`
2. Check Redis connectivity: `redis-cli PING`
3. Use fallback script: `bash scripts/session-invalidation-fallback.sh`

---

## Incident Response Procedures

### Procedure A: Token Leak in Git History

**Timeline**: < 5 minutes

1. Detect: GitHub secret scanning alert
2. Invalidate: Global scope (all users)
3. Rotate: OAuth2-proxy cookie secret (Terraform)
4. Monitor: Error rate spike (expected < 10%)
5. Assess: Check for unauthorized API calls before leak detection
6. Document: Incident report with timeline
7. Post-incident: Review log retention policy

### Procedure B: Account Takeover

**Timeline**: < 15 minutes

1. Detect: User reports suspicious activity or MFA attempt fails
2. Invalidate: User scope (just that user)
3. Reset: Force password reset via identity provider
4. Review: Check user's activity log for unauthorized actions
5. Monitor: Watch for re-authentication from unusual IP
6. Assess: Determine if takeover was successful
7. Document: Timeline and affected resources

### Procedure C: Insider Threat (Suspected)

**Timeline**: < 30 minutes (coordinate with security team)

1. Detect: Suspicious API calls, data exfil, permission escalation
2. Isolate: Disable user account in OAuth provider
3. Invalidate: User scope (revoke active sessions)
4. Review: Full audit log of user's actions
5. Quarantine: Preserve logs/artifacts for investigation
6. Legal: Notify legal team if applicable
7. Monitor: Watch for access attempts (expected: fail)

---

## Governance & Deployment Gating

### When Session Invalidation Blocks Deployment

Session invalidation **BLOCKS** main branch merge if:

1. ✅ Someone triggered `scope=global` invalidation in last 24 hours
   - **Why**: Need to understand what triggered it
   - **Resolution**: SRE review + explicit sign-off
   - **Message**: `"Global session invalidation triggered by <actor> - requires SRE sign-off for production deployment"`

2. ✅ Admin token rotated in last 4 hours
   - **Why**: Verify new token is configured before deploy
   - **Resolution**: Wait 4 hours or verify token in vault
   - **Message**: `"Admin token recently rotated - wait 4 hours before production deployment"`

3. ✅ Breach response procedure triggered (accounts disabled)
   - **Why**: May indicate ongoing incident
   - **Resolution**: Wait for security team clearance
   - **Message**: `"Incident response triggered - deployment blocked until security clearance"`

### Override Process

**Only for verified security:** Authorized: SRE Lead + Security Lead

```bash
# Document override reason
echo "OVERRIDE_REASON: <brief description>" > /tmp/override

# Deploy with override
terraform apply -auto-approve -override-incident=yes
```

---

## Metrics & Monitoring

### Key Metrics

**Session Invalidation Counter**:
```
session_invalidations_total{scope="global|user", actor="admin_id"}
```

**Session Fingerprint Mismatches**:
```
session_fingerprint_mismatch_total{action="log|warn|block"}
```

**Rate Limit Rejections**:
```
admin_rate_limit_exceeded_total{endpoint="sessions_invalidate"}
```

### Alerting Rules

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| Global Session Invalidation | Any `scope=global` | P0 | PagerDuty immediately |
| Admin Token Rotation | Any token regeneration | P1 | SRE review within 1 hour |
| Repeated Rate Limit | 5+ rejections in 5 min | P2 | Investigate abuse |

---

## Related Documentation

- [Session Invalidation Design](../../docs/architecture/session-invalidation.md)
- [Admin Token Management](../../docs/admin/token-management.md)
- [Security Incident Response](../../INCIDENT-RESPONSE.md)
- [OAuth2-proxy Configuration](../../docker-compose.tpl)
- [Vault Integration](../../docs/infrastructure/vault-integration.md)

---

## Contact & Escalation

**On-Call SRE**: PagerDuty (auto-routed on global invalidation)  
**Security Team**: `#security` Slack channel  
**Incident Commander**: Follow incident response procedure  

---

## Training & Certification

| Role | Required? | Last Trained | Next Training |
|------|-----------|--------------|---------------|
| SRE | Yes | [DATE] | [DATE + 3 months] |
| Security Lead | Yes | [DATE] | [DATE + 3 months] |
| DevOps | Yes | [DATE] | [DATE + 6 months] |
| Platform Team | Yes | [DATE] | [DATE + 6 months] |

---

**Version**: 1.0  
**Last Tested**: April 15, 2026  
**Next Review**: May 15, 2026
