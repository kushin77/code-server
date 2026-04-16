# Phase 3: RBAC Enforcement at Service Boundaries

**Issue**: #390 (P1 High) — RBAC Enforcement  
**Phase**: 3 (of 4 for complete IAM)  
**Status**: DESIGNING  
**Effort**: 8-10 hours  
**Dependencies**: Phase 2 Service-to-Service Auth (#389) — In Progress  
**Blocked By**: PR #462 merge (Phase 1) → Phase 2 completion → Phase 3 start  

---

## Executive Summary

Phase 3 enforces fine-grained role-based access control (RBAC) at all service boundaries. Building on Phase 1's RBAC policies and Phase 2's service authentication, Phase 3 implements policy evaluation at the request boundary, ensuring each service can only perform authorized actions on other services.

**Key Deliverables**:
1. OpenPolicyAgent (OPA) policy evaluation at Caddy/service gateway
2. RBAC policy enforcement for all service-to-service requests
3. Dynamic policy reloading (no service restarts)
4. Centralized policy audit trail
5. Runbooks for policy violations and debugging

---

## Architecture

### RBAC Policy Model

```
Service A (JWT)
   │ claims: {subject: "code-server:default", role: "developer"}
   │
   ├─→ Service B (Policy Check)
   │     Is "code-server:default" with role "developer" 
   │     allowed to perform "read-metrics" on Service B?
   │
   └─→ Allowed? Check policy:
       ┌─────────────────────────────────────────────┐
       │ Subject: code-server:default                │
       │ Role: developer                             │
       │ Target: prometheus (service)                │
       │ Action: read-metrics                        │
       │ Result: ✅ ALLOW (policy matches)           │
       │         OR ❌ DENY (no matching policy)     │
       └─────────────────────────────────────────────┘
```

### Policy Structure

```yaml
# roles/developer.yaml
name: developer
description: "Developer role - limited access"
rules:
  - id: read-code-server-logs
    resource: code-server
    actions: [read-logs, read-metrics]
    conditions:
      - namespace: in [default, dev]
      - time: within_business_hours
    effect: allow
    
  - id: no-production-access
    resource: "*.production"
    actions: ["*"]
    effect: deny

# service-policies/prometheus.yaml
service: prometheus
bindings:
  - principal: code-server:default
    role: developer
    scope: metrics-read-only
  - principal: grafana:default
    role: observer
    scope: metrics-read-only
  - principal: admin:*
    role: admin
    scope: full-access
```

---

## Implementation Roadmap

### Phase 3.1: OpenPolicyAgent Deployment (Hours 1-2)

**Objective**: Deploy OPA as policy evaluation engine.

**Tasks**:
1. [ ] Deploy OPA container
   - Image: openpolicyagent/opa:latest
   - Port: 8181
   - Volume: /policies (mounted from ConfigMap)
   - Liveness probe: GET /health

2. [ ] Load initial policies
   - From: `config/opa/policies/`
   - Format: Rego (OPA policy language)
   - Auto-reload on ConfigMap change

3. [ ] Set up OPA data store
   - Store service catalog (all services, endpoints, resources)
   - Store role definitions and bindings
   - Store audit log (all policy decisions)

**Success Criteria**:
- OPA responds at 192.168.168.31:8181/health
- Policies loaded in memory
- Data API accessible

---

### Phase 3.2: Write Comprehensive RBAC Policies (Hours 2-4)

**Objective**: Define all service-to-service authorization rules.

**Policies to Define**:
1. **Code-Server → Prometheus** (metrics read-only)
2. **Code-Server → Loki** (log write)
3. **Code-Server → PostgreSQL** (app data read/write)
4. **Code-Server → Redis** (cache read/write)
5. **Prometheus → Loki** (log queries)
6. **Grafana → Prometheus** (metrics read)
7. **Grafana → Loki** (logs read)
8. **Caddy → All services** (health checks, limited scope)
9. **Admin tools** (full access, audit required)

**Rego Policy Example**:
```rego
package rbac

# Default: deny all access
default allow = false

# Allow read-only access to code-server logs
allow {
    input.subject == "prometheus:default"
    input.target == "code-server"
    input.action == "read-logs"
    input.scope == "summary"  # Summary only, not detailed
}

# Deny access to sensitive operations
deny {
    input.action in ["delete-database", "reset-password", "clear-audit-logs"]
}

# Audit all denied requests
audit_deny[msg] {
    deny
    msg = sprintf("DENY: %s cannot %s on %s", [input.subject, input.action, input.target])
}
```

**Files to Create**:
- `config/opa/policies/rbac.rego` - Core RBAC policy
- `config/opa/policies/audit.rego` - Audit logging policy
- `config/opa/policies/deny-rules.rego` - Explicit deny rules
- `config/opa/data/roles.json` - Role definitions
- `config/opa/data/service-bindings.json` - Service-to-service bindings

**Success Criteria**:
- All service-to-service relationships defined
- Explicit deny list for dangerous operations
- Audit logging for all decisions

---

### Phase 3.3: Enforce Policies at Service Boundaries (Hours 4-6)

**Objective**: Integrate OPA with service routers (Caddy/Envoy).

**Implementation Options**:

**Option A: Caddy Integration (Recommended - simplest)**
```
Incoming Request
   ↓
Caddy (policy.caddy plugin)
   ├─→ Extract: subject (from JWT), target (service), action (HTTP method)
   ├─→ Query OPA: /v1/data/rbac?input={subject, target, action}
   └─→ OPA returns: allow=true/false
       ├─→ true: Forward to target service ✅
       └─→ false: Return 403 Forbidden + log ❌
```

**Option B: Envoy Integration**
```
Incoming Request
   ↓
Envoy (ext_authz filter)
   ├─→ Query OPA for policy decision
   ├─→ Block or allow at LB layer
```

**Option C: Sidecar Policy Agent**
```
Incoming Request
   ↓
Service-specific OPA sidecar
   ├─→ Validates before service processes request
```

**Tasks**:
1. [ ] Implement OPA Caddy middleware
   - Go module: github.com/open-policy-agent/opa/plugins/bundle/caddy_plugin
   - Or custom: call OPA HTTP API before forwarding

2. [ ] Configure policy query format
   ```
   POST /v1/data/rbac?input={
     "subject": "code-server:default",
     "target": "prometheus",
     "action": "read-metrics",
     "resource": "/api/v1/query"
   }
   Response: {"result": {"allow": true}}
   ```

3. [ ] Implement policy caching
   - Cache policy decisions for 5 minutes
   - Invalidate on policy reload
   - Monitor cache hit rate

4. [ ] Error handling
   - If OPA unavailable: fail-closed (deny all, don't crash)
   - Log all failures
   - Alert on repeated OPA unavailability

**Files to Create**:
- `config/caddy/opa-policy.conf` - Caddy policy integration
- `scripts/caddy-opa-plugin.go` - Custom Caddy plugin (if needed)
- `scripts/enforce-opa-policies.sh` - Policy enforcement script

**Success Criteria**:
- All requests evaluated by OPA
- Policies enforced at request boundary
- Cache working and reducing OPA load
- No service downtime during policy deployment

---

### Phase 3.4: Policy Audit & Compliance (Hours 6-8)

**Objective**: Log all RBAC decisions for audit and compliance.

**Tasks**:
1. [ ] Create audit event schema
   ```json
   {
     "timestamp": "2026-04-16T14:30:00Z",
     "subject": "code-server:default",
     "target": "prometheus",
     "action": "read-metrics",
     "decision": "allow",
     "reason": "policy: developer-role-grant",
     "ip": "192.168.168.31",
     "trace_id": "abc123...",
     "tls_cert_subject": "CN=code-server-cert"
   }
   ```

2. [ ] Stream audit logs to Loki
   - Via OPA policy decision logging
   - Or via Caddy audit plugin
   - Immutable storage (append-only)

3. [ ] Create audit queries
   - "Show all access to service X"
   - "Show all denies for principal Y"
   - "Show all policy violations by time"

4. [ ] Implement compliance reports
   - Daily: policy decision summary
   - Weekly: unused policies, anomalies
   - Monthly: access patterns, recommendations

**Files to Create**:
- `config/opa/policies/audit-logging.rego` - Audit policy
- `scripts/audit-queries.sh` - Audit query library
- `docs/RBAC-AUDIT-COMPLIANCE.md` - Audit guide

**Success Criteria**:
- All policy decisions logged
- Audit logs immutable and tamper-proof
- Audit queries responsive
- Compliance reports automatically generated

---

### Phase 3.5: Policy Debugging & Troubleshooting (Hours 8-10)

**Objective**: Tools and runbooks for operational support.

**Tasks**:
1. [ ] Create policy debugger
   - Input: subject, target, action
   - Output: matching rules, deny reasons, audit trail
   - Tool: OPA eval / trace feature

2. [ ] Write troubleshooting runbook
   - Common issues: denied access, unexpected allow, policy rejects valid user
   - Debugging steps: trace policy evaluation, check bindings, verify audit logs
   - Remediation: policy updates, temporary grants, escalation

3. [ ] Implement policy simulation
   - Test policy changes before deployment
   - Simulate: "if we change policy X, who gets denied?"
   - Prevent breaking legitimate access

4. [ ] Create Grafana dashboards
   - RBAC decision rates (allow/deny)
   - Top denied policies
   - Policy reload frequency
   - OPA performance metrics

**Files to Create**:
- `scripts/debug-opa-policy.sh` - Policy debugger
- `docs/RBAC-TROUBLESHOOTING.md` - Troubleshooting guide
- `config/grafana/rbac-dashboard.json` - Grafana dashboard
- `scripts/simulate-policy-change.sh` - Policy simulator

**Success Criteria**:
- Operators can quickly debug policy issues
- All common problems documented with solutions
- Policy changes testable before deployment
- Visibility into RBAC system health

---

## Testing Strategy

### Unit Tests
- Policy logic: subject X can do action Y on resource Z
- Deny rules: sensitive operations always denied
- Audit logging: all decisions recorded

### Integration Tests
- Full request flow: JWT → policy check → allow/deny
- Policy reload: update policy without service restart
- Cache invalidation: cache updates when policy changes

### Operational Tests
- High-load policy evaluation (100+ simultaneous requests)
- OPA failure handling (deny-closed on unavailability)
- Policy debugging tools functional

### Security Tests
- JWT tampering: rejected by policy
- Privilege escalation: denied by policy
- Policy bypass attempts: all fail

---

## Rollback Plan

If Phase 3 fails:
1. **Disable OPA enforcement**: revert to Phase 2 (service identity still works)
2. **Broken policies**: restore previous policy version
3. **OPA down**: services continue with cached decisions (up to 5 min old)

**Recovery Time**: < 5 minutes for any scenario

---

## Success Criteria

✅ **Implementation Complete**:
- OPA deployed and operational
- All RBAC policies defined and tested
- Policies enforced at all service boundaries
- Audit logging working
- Debugging tools operational

✅ **Testing Complete**:
- Unit tests: 100% pass
- Integration tests: all flows working
- Load testing: 100+ concurrent requests handled
- Security testing: all attacks blocked

✅ **Production Ready**:
- Fine-grained access control enforced
- No unauthorized service-to-service communication
- Complete audit trail for compliance
- Fast policy debugging for support team

---

## Timeline

| Task | Effort | Owner |
|------|--------|-------|
| OPA Deployment | 2h | @infra-team |
| RBAC Policies | 2h | @kushin77 |
| Policy Enforcement | 2h | @backend-team |
| Audit & Compliance | 2h | @security-team |
| Debugging & Ops | 2h | @platform-team |
| **Total Phase 3** | **10h** | **Full team** |

---

## Notes

- **Rego language**: OPA's policy language, similar to Prolog
- **Deny-by-default**: only explicitly allowed requests pass
- **Audit-everything**: all decisions logged for compliance (GDPR, SOC2, ISO27001)
- **Dynamic policies**: no service restarts needed for policy changes

---

**Status**: Ready for implementation after Phase 2 completes  
**Next Phase**: Phase 4 - Compliance Automation (4-6 hours)  
**Owner**: @kushin77 (can distribute to team)  

---

Last Updated: April 16, 2026  
Session: #3 (Execution Phase)
