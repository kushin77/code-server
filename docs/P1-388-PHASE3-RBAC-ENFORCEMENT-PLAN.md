# P1 #388 Phase 3: RBAC Enforcement & Service Integration
# Implementing authorization checks and audit logging

**Status**: PLANNED (follows Phase 2)  
**Estimated Effort**: 8-10 hours  
**Dependencies**: Phase 1 + Phase 2 complete  

---

## Phase 3 Scope

Phase 3 implements actual enforcement of RBAC policies created in Phase 1, integrating identity checks into the runtime platform:

### 1. OAuth2-Proxy JWT Validation Integration
- Extract JWT claims from oauth2-proxy
- Pass role information to backend services
- Validate signature and expiration
- Check token age (ensure not too old)

### 2. Caddyfile Reverse Proxy Authentication
- Add auth middleware to protected routes
- Extract X-Auth-Request-* headers from oauth2-proxy
- Pass headers downstream to services
- Enforce MFA requirements by route

### 3. Service-Level RBAC Enforcement
- Backend services validate role from JWT
- Check service-specific permissions
- Log authorization decisions
- Return 403 Forbidden for denied requests

### 4. Audit Logging Integration
- Send all auth decisions to Loki + PostgreSQL
- Include correlation ID for tracing
- Log user/service, action, resource, result
- Alert on policy violations

### 5. Break-Glass Emergency Access
- Bypass mechanism for authentication failures
- MFA exemption for break-glass tokens
- Audit trail for all break-glass usage
- Automatic expiration (max 1 hour)

---

## Implementation Steps

### Step 1: OAuth2-Proxy Configuration
**Time**: 1-2 hours

```bash
# config/oauth2-proxy.cfg updates

# Enable JWT validation
oidc_verify_signature = true
oidc_claim_groups = roles

# Extract roles from JWT
set_authorization_header = true
headers_claim_groups = roles
headers_claim_email = email
headers_claim_id = sub

# Role-based access control
require_groups = "viewer,operator,admin"

# Allowed groups per endpoint (example)
# /api/admin/* -> admin only
# /api/operator/* -> operator,admin
# /api/* -> viewer,operator,admin
```

### Step 2: Caddyfile Integration
**Time**: 1-2 hours

```caddy
# caddyfile updates for P1 #388 Phase 3

# OAuth2-proxy endpoint
http://oauth2-proxy:4180 {
  # Validate JWT signature
  uri /auth
  
  # Headers to extract from auth response
  auth_request_uri /auth
  copy_headers X-Auth-Request-Email
  copy_headers X-Auth-Request-User
  copy_headers X-Auth-Request-Groups
  copy_headers X-Auth-Request-Id-Token
}

# Protected admin routes (admin role only)
@admin {
  path /admin/*
  header X-Auth-Request-Groups admin
}

# Protected operator routes (operator+ role)
@operator {
  path /api/deployments/*
  header X-Auth-Request-Groups "operator|admin"
}

# Protected viewer routes (viewer+ role)
@protected {
  path /api/metrics/*
  header X-Auth-Request-Groups "viewer|operator|admin"
}

# Enforce MFA for sensitive operations
@mfa_required {
  path /admin/secrets/*
  path /api/deployments/destroy
}
```

### Step 3: Backend Service RBAC
**Time**: 2-3 hours

Example Backstage integration:

```python
# backend/src/auth/rbac.py

class RBACEnforcer:
    def check_permission(self, user_context, action, resource):
        """
        Check if user has permission for action on resource
        
        Args:
            user_context: JWT claims (roles, email, sub)
            action: "read", "write", "delete"
            resource: "catalog", "services", "secrets"
        
        Returns:
            (allowed: bool, reason: str)
        """
        
        # Extract role from user context
        roles = user_context.get('roles', [])
        
        # Check RBAC policy (from config/iam/rbac-policies.yaml)
        policy = self.load_policy()
        
        for role in roles:
            if policy.allows(role, action, resource):
                return True, None
        
        return False, f"No role grants {action} on {resource}"
    
    def audit_decision(self, user_context, action, resource, allowed, reason):
        """Log authorization decision to audit service"""
        
        audit_event = {
            'event_type': 'authorization.access_granted' if allowed else 'authorization.access_denied',
            'actor_id': user_context['sub'],
            'action': action,
            'resource': resource,
            'roles': user_context['roles'],
            'result_status': 'success' if allowed else 'denied',
            'result_reason': reason,
            'timestamp': datetime.utcnow().isoformat(),
            'correlation_id': request.headers.get('X-Correlation-ID')
        }
        
        self.logger.audit(audit_event)


# Example usage in API route
@app.route('/api/catalog/update', methods=['POST'])
def update_catalog():
    user_context = extract_jwt_claims(request.headers)
    
    rbac = RBACEnforcer()
    allowed, reason = rbac.check_permission(user_context, 'write', 'backstage:catalog')
    
    if not allowed:
        rbac.audit_decision(user_context, 'write', 'backstage:catalog', False, reason)
        return {'error': reason}, 403
    
    # Proceed with update
    result = update_catalog_service(request.json)
    
    rbac.audit_decision(user_context, 'write', 'backstage:catalog', True, 'Success')
    return result, 200
```

### Step 4: Audit Logging to Loki + PostgreSQL
**Time**: 1-2 hours

```bash
# scripts/send-audit-event.sh

# Send audit event to Loki
send_to_loki() {
    local event=$1
    
    curl -s -X POST http://loki:3100/loki/api/v1/push \
      -H "Content-Type: application/json" \
      -d '{
        "streams": [{
          "stream": {
            "service": "iam-audit",
            "event_type": "'"${event['event_type']}"'",
            "severity": "info"
          },
          "values": [
            ["'$(date +%s%N)'", "'"$(echo $event | jq -c)"'"]
          ]
        }]
      }'
}

# Send to PostgreSQL (immutable audit table)
send_to_postgresql() {
    local event=$1
    
    psql -h postgres -U audit_user -d audit_logs -c "
    INSERT INTO iam_audit_events (
        event_id, event_timestamp, event_type, actor_id,
        action, resource_type, result_status, raw_event_json
    ) VALUES (
        '${event[event_id]}',
        '${event[timestamp]}',
        '${event[event_type]}',
        '${event[actor_id]}',
        '${event[action]}',
        '${event[resource_type]}',
        '${event[result_status]}',
        '${event}'::jsonb
    );
    "
}
```

### Step 5: Break-Glass Emergency Access
**Time**: 1 hour

```yaml
# config/iam/break-glass-policy.yaml

break_glass:
  # Emergency access token (high-privilege, short-lived)
  enabled: true
  
  # Who can issue break-glass tokens
  authorized_issuers:
    - "kushin77"  # Repository owner
    - "security-team"  # Security team
  
  # Break-glass token properties
  token:
    ttl_seconds: 3600  # 1 hour max
    can_bypass_mfa: true
    can_bypass_rbac: false  # Still check basic roles
    elevated_role: "break-glass-admin"
  
  # Audit requirements
  audit:
    log_immediately: true
    require_approval_reason: true
    alert_on_issuance: true
    alert_recipients: ["security@kushin.cloud"]
  
  # Recovery procedures
  recovery:
    disable_after_hours: false
    require_ticket_number: true
    auto_disable_after_use: false
    session_recording: true
```

### Step 6: Query Interface for Audit Logs
**Time**: 1-2 hours

```bash
# scripts/query-audit-logs.sh

query_by_user() {
    local user_id=$1
    local start_time=${2:-"1h ago"}
    
    # LogQL query
    curl -s 'http://loki:3100/loki/api/v1/query_range' \
      --data-urlencode 'query={service="iam-audit"} | json | actor_id="'"$user_id"'"' \
      --data-urlencode "start=$(date +%s -d "$start_time")" \
      --data-urlencode "end=$(date +%s)"
}

query_by_action() {
    local action=$1
    
    curl -s 'http://loki:3100/loki/api/v1/query_range' \
      --data-urlencode 'query={service="iam-audit"} | json | action="'"$action"'"'
}

query_denials() {
    # All access denied events in last 24 hours
    curl -s 'http://loki:3100/loki/api/v1/query_range' \
      --data-urlencode 'query={service="iam-audit"} | json | result_status="denied"'
}

# Export to CSV
export_audit_logs() {
    local format=${1:-"csv"}
    
    psql -h postgres -U audit_user -d audit_logs \
      -c "\COPY (SELECT * FROM iam_audit_events ORDER BY event_timestamp DESC) TO STDOUT WITH CSV HEADER"
}
```

---

## Success Criteria

- [ ] OAuth2-proxy validates JWTs and extracts roles
- [ ] Caddyfile enforces role-based routing
- [ ] Backend services check permissions before operations
- [ ] All authorization decisions logged (100% audit coverage)
- [ ] Query audit logs by user/action/time (latency < 1s)
- [ ] Break-glass tokens work and are properly audited
- [ ] Deny operations show clear "access denied" errors with reason
- [ ] Load test: 1000 req/s with auth checks, p95 latency < 200ms
- [ ] Backward compatibility: existing authenticated users still work

---

## Integration Checklist

Phase 3 requires Phase 1 + 2 to be complete:

- [x] Phase 1: OIDC config, JWT schema, role mapping
- [x] Phase 2: Workload federation, service account mappings
- [ ] Phase 3: RBAC enforcement (this phase)

Phase 3 unblocks:

- [ ] Phase 4: Compliance & audit reporting
- [ ] P1 #385: Dual-Portal Architecture (Backstage + Appsmith)
- [ ] P2 #418: Terraform modules (all identity-protected)

---

## Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| RBAC too strict, locks out users | Gradual rollout: viewer role first, then operator, then admin |
| JWT validation too slow | Implement caching layer (Redis), async validation |
| Break-glass tokens misused | Require approval ticket, session recording, time limits |
| Audit logs overflow | Partition by date, archive to S3 after 90 days |
| Emergency break-glass expired | Automated renewal for approved use cases, admin notification |

---

## Next Steps (Phase 4: Compliance)

Phase 4 focuses on audit reporting, log retention, and compliance:

1. Audit log retention policies (2-7 years)
2. Automated compliance reports (GDPR, SOC2, ISO27001)
3. Log immutability verification
4. Break-glass emergency access audit trail
5. User revocation and access cleanup
6. Incident response playbooks
7. External audit readiness

---

## Files to be Created (Phase 3)

```
config/iam/
├── break-glass-policy.yaml
└── rbac-enforcement-config.yaml

scripts/
├── enforce-rbac-phase3.sh
└── query-audit-logs.sh

docs/
└── P1-388-PHASE3-RBAC-ENFORCEMENT.md
```

**Total Effort**: 8-10 hours (1 day)  
**Blocking**: P1 #385, P2 #418 Phase 3+  
**Related**: P1 #388 (main issue)
