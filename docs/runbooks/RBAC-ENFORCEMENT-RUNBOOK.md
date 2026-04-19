# RBAC Enforcement (Phase 3) Operational Runbook

## Overview

This runbook covers operational procedures for the Phase 3 RBAC enforcement layer that validates and controls access to all protected endpoints.

## Alerting: High Denial Rate

**Alert**: `RBACHighDenialRate` (>5% of requests denied)

### Symptoms
- Legitimate users getting 403 Forbidden errors
- Increase in error logs from frontend applications
- Performance may appear normal (denials are fast)

### Diagnosis

```bash
# Check recent denials (last hour)
psql -d code_server -c "SELECT * FROM audit_denials_last_hour ORDER BY denial_count DESC LIMIT 10;"

# Check denial breakdown by role
psql -d code_server -c "SELECT role, reason, COUNT(*) FROM audit_logs WHERE action='deny' AND timestamp > NOW() - INTERVAL '1 hour' GROUP BY role, reason;"

# Check if policy was recently updated
git log -n 5 --oneline -- config/iam/rbac-policy-phase3.yaml
```

### Resolution

**If policy was recently updated**:
1. Verify the policy change doesn't inadvertently block legitimate users
2. Roll back: `git revert <commit>`
3. Redeploy: `terraform apply -auto-approve`

**If policy unchanged but denials increasing**:
1. Check if users' roles changed: `SELECT DISTINCT role FROM audit_logs WHERE timestamp > NOW() - INTERVAL '1 hour' GROUP BY role;`
2. If specific role is being denied, verify role is in `allow_roles` list for that endpoint
3. Check JWT token expiration: tokens older than 1 hour may have stale claims

**If specific endpoint is affected**:
```bash
# Find what's being denied
psql -d code_server -c "SELECT path, method, role, reason, COUNT(*) FROM audit_logs WHERE action='deny' AND timestamp > NOW() - INTERVAL '1 hour' GROUP BY path, method, role, reason;"

# Example: If /admin/deploy is denying 'operator' role
# Fix: Add 'operator' to allow_roles in config/iam/rbac-policy-phase3.yaml
```

## Troubleshooting: User Getting 403

### User says: "I can't access `/admin/deploy`"

**Step 1**: Verify their JWT token
```bash
# Extract JWT from request
# Authorization header should be: Bearer eyJhbGc...

# Decode JWT (without verification):
echo $JWT | jq -R 'split(".") | .[1] | @base64d | fromjson'

# Expected claims:
# {
#   "sub": "user@company.com",
#   "role": "admin",
#   "identity_type": "human",
#   "exp": 1713916800
# }
```

**Step 2**: Check if their role has permission
```bash
# Check policy for /admin/deploy
grep -A 5 "/admin/deploy:" config/iam/rbac-policy-phase3.yaml

# Should show: allow_roles: [admin]
# If user's role is "operator", they need "admin" role
```

**Step 3**: Check audit log entry
```bash
psql -d code_server -c "SELECT timestamp, user_id, role, action, reason FROM audit_logs WHERE path='/admin/deploy' AND user_id='user@company.com' ORDER BY timestamp DESC LIMIT 5;"

# Example output:
# timestamp             | user_id             | role     | action | reason
# 2026-04-23 14:35:00 | user@company.com    | operator | deny   | insufficient_role

# This confirms: user has "operator" role, but endpoint requires "admin"
```

**Resolution**:
1. Check with team if user should have "admin" role
2. If yes: Update user's role in GitHub team or directory service
3. If no: User needs to request feature from admin user
4. Verify with: `curl -H "Authorization: Bearer $JWT" https://api.company.com/admin/deploy`

## Troubleshooting: All Users Denied

### Alert: `RBACHighDenialRate` suddenly >90%

**This indicates a complete policy failure** (e.g., policy file missing or corrupted)

### Diagnosis

```bash
# Check if policy file exists
ls -la config/iam/rbac-policy-phase3.yaml

# Check Caddy reload logs
docker logs caddy | grep -i "jwt\|policy"

# Check if RBAC module is enabled
grep "rbac_enforcer" config/caddy/Caddyfile

# Check Prometheus: rbac_decision_total{action="allow"} should be increasing
curl http://localhost:9090/api/v1/query?query=rbac_decision_total
```

### Resolution

**If policy file is missing**:
1. Regenerate: `bash scripts/configure-rbac-enforcement-phase3.sh`
2. Verify: `ls config/iam/rbac-policy-phase3.yaml`
3. Reload Caddy: `docker exec caddy /caddy reload`

**If policy is corrupted (invalid YAML)**:
1. Check for syntax errors: `yamllint config/iam/rbac-policy-phase3.yaml`
2. Restore from git: `git checkout config/iam/rbac-policy-phase3.yaml`
3. Reload Caddy: `docker exec caddy /caddy reload`

**If Caddy reload failed**:
1. Check logs: `docker logs caddy | tail -50`
2. Validate Caddyfile syntax: `caddy validate --config config/caddy/Caddyfile`
3. Restart: `docker restart caddy`

## Performance Tuning: High Latency

### Alert: `RBACPolicyEvalLatencyHigh` (p99 > 10ms)

**This is unusual** — policy evaluation should be <1ms

### Diagnosis

```bash
# Check policy evaluation time histogram
curl http://localhost:9090/api/v1/query?query=rbac_policy_eval_seconds_bucket

# Check database latency
psql -d code_server -c "SELECT EXTRACT(EPOCH FROM (NOW() - NOW())) * 1000 as latency_ms;"

# Check system load
docker stats --no-stream | head -5
```

### Resolution

**If database slow**:
1. Check PostgreSQL logs: `docker logs postgres | tail -50`
2. Analyze slow queries: `SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;`
3. Possible causes: missing indexes, table bloat, long-running transactions
4. Run VACUUM: `psql -d code_server -c "VACUUM ANALYZE;"`

**If system overloaded**:
1. Check CPU/memory: `docker stats`
2. Check number of active connections: `psql -d code_server -c "SELECT count(*) FROM pg_stat_activity;"`
3. If >100 connections: implement connection pooling (pgBouncer)

## Audit Logging: Compliance Queries

### "Show me all admin actions in the past 24 hours"

```bash
psql -d code_server -c "
  SELECT timestamp, user_id, path, method, action, reason
  FROM audit_logs
  WHERE path LIKE '/admin/%'
    AND timestamp > NOW() - INTERVAL '24 hours'
  ORDER BY timestamp DESC;
"
```

### "Show me who accessed sensitive endpoints"

```bash
psql -d code_server -c "
  SELECT timestamp, user_id, role, path, method, action
  FROM audit_logs
  WHERE path IN ('/admin/deploy', '/admin/restart')
    AND timestamp > NOW() - INTERVAL '7 days'
  ORDER BY timestamp DESC;
"
```

### "Generate monthly compliance report (RBAC enforcement summary)"

```bash
psql -d code_server << 'SQL'
SELECT 
  DATE_TRUNC('month', timestamp) as month,
  role,
  COUNT(*) as total_requests,
  COUNT(CASE WHEN action='allow' THEN 1 END) as allowed,
  COUNT(CASE WHEN action='deny' THEN 1 END) as denied,
  ROUND(100.0 * COUNT(CASE WHEN action='deny' THEN 1 END) / COUNT(*), 2) as deny_percent
FROM audit_logs
WHERE timestamp > NOW() - INTERVAL '3 months'
GROUP BY DATE_TRUNC('month', timestamp), role
ORDER BY month DESC, role;
SQL
```

---

**Runbook Owner**: Infrastructure Team  
**Last Updated**: April 23, 2026  
**Status**: Production  
