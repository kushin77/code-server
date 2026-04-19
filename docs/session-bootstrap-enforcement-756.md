# Session Bootstrap Enforcement - Implementation Guide

**Issue**: #756  
**Module**: `src/services/session-bootstrap-enforcer/`  
**Status**: ✅ Implementation Complete  
**Date**: April 18, 2026

---

## Overview

This document describes the mandatory session bootstrap enforcement that ensures all code-server sessions are backed by a valid, cryptographically-signed assertion from the admin portal. Every session must pass a multi-stage validation pipeline before activation.

## Architecture

### Bootstrap Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User Login at Portal (admin)                                │
│  - Validates user credentials                              │
│  - Checks roles & entitlements                             │
│  - Generates signed assertion (JWT)                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    Assertion (JWT)
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Code-Server Session Bootstrap                               │
│                                                              │
│ 1. ASSERTION_RECEIVED                                       │
│    └─ Accept JWT from client                               │
│                                                              │
│ 2. ASSERTION_VALIDATION_STARTED                            │
│    └─ Decode and extract policy bundle                     │
│                                                              │
│ 3. SIGNATURE_VERIFIED                                       │
│    └─ Verify RS256 signature using issuer public key       │
│    └─ Validate issuer & audience claims                    │
│                                                              │
│ 4. POLICY_BUNDLE_VERIFIED                                   │
│    └─ Check expiry (iat, exp)                              │
│    └─ Validate version compatibility                       │
│    └─ Validate identity fields (email, roles, org)         │
│                                                              │
│ 5. SESSION_ACTIVATED                                        │
│    └─ Create session context                               │
│    └─ Cache verified bundle                                │
│    └─ Store session state                                  │
│                                                              │
│ SUCCESS: Session ready for IDE access                       │
│ FAILURE: Fail-safe mode activated                          │
└──────────────────────────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Privileged Operation Enforcement                            │
│  - Session still valid? (not expired, not revoked)         │
│  - Policy still valid? (not expired)                       │
│  - Fail-safe mode? (deny-all blocks all ops)               │
│  - Policy allows operation? (whitelist check)              │
│  - Policy drift? (local modifications detected)            │
│                                                              │
│  → If all checks pass: Operation allowed                    │
│  → If any check fails: Operation denied                     │
└──────────────────────────────────────────────────────────────┘
```

### Bootstrap Stages

| Stage | Purpose | Validation | Failure Behavior |
|-------|---------|-----------|------------------|
| 1. Assertion Received | Accept JWT token | JWT format valid | Reject with INVALID_JWT_FORMAT |
| 2. Validation Started | Decode & extract | Bundle structure present | Reject with INVALID_BUNDLE_FORMAT |
| 3. Signature Verified | Cryptographic proof | RS256 + issuer claims | Reject with INVALID_SIGNATURE |
| 4. Policy Verified | Policy integrity | Expiry, version, identity | Reject with policy errors |
| 5. Session Activated | Create session state | All checks passed | Activate session |

---

## Implementation Details

### 1. Session Context

Each bootstrap creates a `SessionContext` with:

```typescript
interface SessionContext {
  session_id: string              // Unique identifier
  user: {
    email: string                 // User email from assertion
    sub: string                   // Stable user ID
    roles: string[]               // e.g., ["developer", "admin"]
    org: string                   // Organization ID
  }
  policy: {
    bundle: PolicyBundle          // Verified policy bundle
    valid: boolean                // Is policy currently valid
    enforcement_mode: EnforcementMode // STRICT | DEGRADED | LOCKED_DOWN
    policy_version: string        // e.g., "1.0"
    policy_expires_at: number     // Unix timestamp
  }
  authenticated_at: number        // When session was created
  expires_at: number              // Session TTL expiry
  fail_safe_active: boolean       // Is fail-safe mode active?
  fail_safe_mode?: FailSafeMode   // deny-all | deny-mutating | read-only-cache
  correlation_id: string          // For audit trail correlation
  audit_trail: AuditEvent[]       // Chronological event log
}
```

### 2. Enforcement Modes

| Mode | Behavior | When Active |
|------|----------|------------|
| **STRICT** | All policy checks enforced, full IDE access if passed | Normal operation |
| **DEGRADED** | Some checks disabled, reduced functionality | Fail-safe active with cached policy |
| **LOCKED_DOWN** | No operations allowed, read-only at best | Fail-safe active without cache |

### 3. Privileged Operations

Operations that require policy enforcement:

```typescript
type PrivilegedOperation =
  | "read_secret"              // Access GSM secrets
  | "execute_terminal"         // Run shell commands
  | "install_extension"        // Install marketplace extensions
  | "modify_workspace"         // Edit workspace settings
  | "git_credential_access"    // Use git credentials
  | "break_glass"              // Emergency override
```

Each operation is checked against:
- Session validity (not expired)
- Policy validity (not expired)
- Fail-safe mode (deny-all blocks all)
- Policy whitelist (operation allowed?)
- Policy drift (local modifications?)

### 4. Audit Trail

All events are recorded with:
- Timestamp (Unix epoch)
- Event type (bootstrap, operation, error)
- Status (success, failure)
- Details (context-specific data)
- Correlation ID (trace across logs)

**Event Types**:

**Bootstrap Events**:
- `ASSERTION_RECEIVED`
- `ASSERTION_VALIDATION_STARTED`
- `SIGNATURE_VERIFIED`
- `POLICY_BUNDLE_VERIFIED`
- `SESSION_ACTIVATED`
- `BOOTSTRAP_FAILED`
- `FAIL_SAFE_ACTIVATED`

**Operation Events**:
- `PRIVILEGED_OP_ATTEMPTED`
- `PRIVILEGED_OP_ALLOWED`
- `PRIVILEGED_OP_DENIED`
- `POLICY_DRIFT_DETECTED`

### 5. Fail-Safe Modes

When portal is unreachable or policy invalid:

| Scenario | Mode | Behavior |
|----------|------|----------|
| Valid cached policy available | `READ_ONLY_CACHE` | Use cached policy, read-only IDE |
| No cached policy | `DENY_MUTATING` | Allow read-only IDE access |
| Critical error | `DENY_ALL` | Full lockout, no access |

---

## Bootstrap Integration Points

### Code-Server Startup

```typescript
// In code-server bootstrap entrypoint:
import { createPolicyBundleVerifier } from "@services/policy-bundle-verifier"
import { createSessionBootstrapEnforcer } from "@services/session-bootstrap-enforcer"

async function startCodeServer(options) {
  // Get assertion from environment or request
  const assertion = process.env.POLICY_ASSERTION || req.headers["x-policy-assertion"]

  // Create verifier with portal config
  const verifier = createPolicyBundleVerifier({
    expectedIssuer: "https://kushnir.cloud",
    expectedAudience: "code-server",
  })

  // Create enforcer
  const enforcer = createSessionBootstrapEnforcer(verifier)

  // Bootstrap session
  const result = await enforcer.bootstrap({
    assertion,
    sessionTtlSeconds: 3600, // 1 hour default
  })

  if (!result.success) {
    // Log all errors
    console.error("Bootstrap failed:", result.errors)
    
    // Enter fail-safe mode
    process.env.FAIL_SAFE_MODE = "deny-all"
    
    // Still try to start with degraded capability
    return startInFailSafeMode()
  }

  // Session is valid - store context
  req.session = result.session

  // Start IDE with enforced policy
  return startIDEWithPolicy(result.session.policy)
}
```

### Privileged Operation Interception

```typescript
// Middleware for any operation that requires policy enforcement
app.use(async (req, res, next) => {
  if (req.method === "POST" || req.method === "DELETE") {
    // Get session from storage
    const session = enforcer.getSession(req.sessionId)
    
    // Determine operation type
    const operation = determineOperation(req.path, req.body)
    
    // Check enforcement
    const result = await enforcer.checkPrivilegedOperation(req.sessionId, operation)
    
    if (!result.allowed) {
      auditLog("PRIVILEGED_OP_DENIED", {
        reason: result.reason,
        sessionId: req.sessionId,
      })
      return res.status(403).json({ error: "Operation not allowed" })
    }
    
    // Operation allowed - continue
    next()
  }
})
```

---

## Rollout Plan

### Phase 1: Development & Testing ✅ (COMPLETE)

**Week 1**: Implementation
- [x] SessionBootstrapEnforcer class (450+ lines)
- [x] Type definitions and interfaces
- [x] Audit event recording
- [x] Privileged operation checks
- [x] Policy drift detection (placeholder)
- [x] Fail-safe mode support

**Week 1**: Testing
- [x] 8 test suites covering 30+ scenarios
  - Valid bootstrap flow
  - Invalid assertion rejection
  - Session lifecycle
  - Privileged operation enforcement
  - Policy expiry tracking
  - Fail-safe activation
  - Audit trail correctness
  - Multiple identity types

### Phase 2: Integration Testing (1 week)

#### Week 2 Activities
- [ ] Integrate with code-server startup
- [ ] Test with real portal-issued assertions
- [ ] Load test: bootstrap 100 concurrent sessions
- [ ] Verify audit trail completeness
- [ ] Test fail-safe activation on portal outage
- [ ] Validate privileged operation interception

#### Success Criteria
- [ ] 100% of valid assertions bootstrap successfully
- [ ] Invalid assertions rejected with correct error codes
- [ ] Privileged operations blocked when policy invalid
- [ ] Fail-safe mode activates correctly on portal unavailability
- [ ] Audit trail captures all events with correlation IDs

### Phase 3: Staging Deployment (1 week)

#### Pre-Staging Checklist
- [ ] All tests passing
- [ ] Code review approved (2+ reviewers)
- [ ] Documentation complete
- [ ] Rollback procedure tested

#### Staging Steps

1. **Deploy enforcer module to staging**
   ```bash
   rsync -av src/services/session-bootstrap-enforcer/ \
     staging.code-server:/opt/code-server/src/services/session-bootstrap-enforcer/
   ```

2. **Enable enforcer in code-server bootstrap**
   ```bash
   # Update code-server entrypoint to use enforcer
   export ENFORCE_POLICY_BOOTSTRAP=true
   docker-compose restart code-server
   ```

3. **Monitor bootstrap events**
   ```bash
   # Watch audit logs for bootstrap events
   docker logs -f code-server | grep -i "bootstrap\|assertion\|verification"
   ```

4. **Run integration tests**
   ```bash
   npm test -- session-bootstrap-enforcer --integration
   ```

5. **Test fail-safe mode**
   ```bash
   # Simulate portal outage
   # Verify fail-safe activation and session degradation
   ```

### Phase 4: Production Canary (3 days)

#### Canary (5% traffic)
- Update 1 of 20 production instances
- Monitor for 4 hours

#### Early Production (25% traffic)
- Update 5 of 20 instances
- Monitor for 8 hours

#### Full Production (100% traffic)
- Update all instances
- Full monitoring active

---

## Configuration Reference

### Environment Variables

```bash
# Policy verification (from #740)
POLICY_ISSUER_URL=https://kushnir.cloud
POLICY_ALLOW_UNSIGNED=false  # Require real signatures in production

# Bootstrap enforcement
ENFORCE_POLICY_BOOTSTRAP=true  # Enable mandatory assertion at startup
POLICY_ASSERTION_TTL_SECONDS=3600  # Default session TTL

# Fail-safe
FAIL_SAFE_MODE=deny-mutating  # Default fail-safe mode
FAIL_SAFE_CACHE_TTL_SECONDS=600  # Use cached policy for 10 min

# Audit
AUDIT_SINK_URL=/var/log/code-server/audit.log
AUDIT_CORRELATION_ID_REQUIRED=true

# Enforcement
ENFORCE_PRIVILEGED_OPS=true  # Require policy check for operations
STRICT_POLICY_ENFORCEMENT=true  # STRICT mode (vs DEGRADED)
```

### Runtime Configuration

```typescript
const enforcer = createSessionBootstrapEnforcer(verifier)

const result = await enforcer.bootstrap({
  assertion: request.headers["x-policy-assertion"],
  sessionTtlSeconds: 3600,
  defaultFailSafeMode: FailSafeMode.DENY_MUTATING,
  enforcementMode: EnforcementMode.STRICT,
})
```

---

## Rollback Procedure

### Immediate Rollback (Emergency)

If bootstrap is blocking all sessions:

```bash
# 1. Disable bootstrap enforcement
export ENFORCE_POLICY_BOOTSTRAP=false

# 2. Restart code-server
docker-compose restart code-server

# 3. Monitor recovery
watch 'docker logs code-server | grep "session_start" | wc -l'

# 4. Investigate root cause
docker logs code-server | grep -i "bootstrap\|assertion\|verification"
```

### Planned Rollback

1. Disable enforcer flag
2. Restart services
3. Verify sessions work
4. Investigate and fix
5. Redeploy when ready

---

## Monitoring & Alerting

### Key Metrics

```prometheus
# Bootstrap success/failure
code_server_bootstrap_total{status="success|failure"}
code_server_bootstrap_errors_total{code="INVALID_JWT|INVALID_SIGNATURE|..."}

# Performance
code_server_bootstrap_duration_seconds{quantile="0.99"}

# Privileged operations
code_server_privileged_ops_allowed_total
code_server_privileged_ops_denied_total

# Fail-safe
code_server_fail_safe_activations_total{mode="deny-all|deny-mutating|read-only-cache"}

# Active sessions
code_server_active_sessions_total
code_server_sessions_expired_total
```

### Alert Rules

```yaml
# Critical: High bootstrap failure rate
- alert: BootstrapFailureRate
  expr: |
    rate(code_server_bootstrap_errors_total[5m])
    / rate(code_server_bootstrap_total[5m]) > 0.05
  for: 5m
  annotations:
    summary: "Bootstrap failure rate >5% on {{ $labels.instance }}"

# Warning: Frequent fail-safe activations
- alert: HighFailSafeActivations
  expr: rate(code_server_fail_safe_activations_total[5m]) > 0.01
  for: 10m
  annotations:
    summary: "Fail-safe mode activated frequently on {{ $labels.instance }}"

# Critical: Privileged ops blocked
- alert: HighPrivilegedOpDenialRate
  expr: |
    rate(code_server_privileged_ops_denied_total[5m])
    / rate(code_server_privileged_ops_allowed_total[5m] + code_server_privileged_ops_denied_total[5m]) > 0.1
  for: 10m
  annotations:
    summary: "Privileged operations blocked >10% on {{ $labels.instance }}"
```

---

## Testing Scenarios

### Scenario 1: Valid Bootstrap
**Input**: Valid JWT assertion with properly signed policy bundle  
**Expected**: Session created, audit events logged, user can access IDE  
**Test**: `bootstrap.spec.ts` - Test 1.1

### Scenario 2: Invalid Assertion
**Input**: Malformed JWT  
**Expected**: Bootstrap fails with INVALID_JWT_FORMAT error  
**Test**: `bootstrap.spec.ts` - Test 2.1

### Scenario 3: Missing Identity Fields
**Input**: Valid JWT but missing required identity fields  
**Expected**: Bootstrap fails with MISSING_IDENTITY_FIELD errors  
**Test**: `bootstrap.spec.ts` - Test 2.2

### Scenario 4: Expired Session
**Input**: Valid bootstrap, then wait for expiry  
**Expected**: Privileged operations denied  
**Test**: `bootstrap.spec.ts` - Test 3.2

### Scenario 5: Privileged Operation Allowed
**Input**: Valid session, privileged operation  
**Expected**: Operation allowed with audit event  
**Test**: `bootstrap.spec.ts` - Test 3.1

### Scenario 6: Privileged Operation Denied (No Session)
**Input**: Non-existent session, privileged operation  
**Expected**: Operation denied  
**Test**: `bootstrap.spec.ts` - Test 3.3

### Scenario 7: Fail-Safe Activation
**Input**: Bootstrap failure, no cached policy  
**Expected**: Fail-safe mode activated with deny-all  
**Test**: `bootstrap.spec.ts` - Test 6.1

### Scenario 8: Policy Expiry Tracking
**Input**: Policy expires before session expires  
**Expected**: Operations denied after policy expiry  
**Test**: `bootstrap.spec.ts` - Test 5.1

### Scenario 9: Session Termination
**Input**: Valid session, then terminate  
**Expected**: Subsequent operations denied  
**Test**: `bootstrap.spec.ts` - Test 4.3

### Scenario 10: Audit Trail Correlation
**Input**: Bootstrap and operations  
**Expected**: All events have same correlation ID  
**Test**: `bootstrap.spec.ts` - Test 7.1

---

## Known Limitations & Future Work

### Phase 1 (Complete) ✅
- [x] Bootstrap with mandatory assertion validation
- [x] Privileged operation enforcement
- [x] Fail-safe mode support
- [x] Audit trail recording
- [x] Session lifecycle management

### Phase 2 (Future)
- [ ] Policy drift detection (full implementation)
- [ ] Break-glass override mechanism
- [ ] Rate limiting on bootstrap
- [ ] Metrics & observability integration
- [ ] Performance optimization

### Known Gaps
1. **Drift Detection**: Currently placeholder, needs file/env monitoring
2. **Break-Glass**: No emergency override mechanism yet
3. **Rate Limiting**: No protection against bootstrap brute-force
4. **Metrics**: Audit trail complete, but Prometheus integration pending

---

## Success Metrics

**Bootstrap**:
- 99.99% success rate for valid assertions
- <50ms bootstrap time (p99)
- 100% of failures logged to audit trail

**Enforcement**:
- 0 privilege escalation incidents
- 100% of privileged ops enforced
- <5ms operation check time (p99)

**Fail-Safe**:
- <100ms activation time
- 100% of sessions degraded correctly
- 0 data loss incidents

---

## Support & Escalation

### Questions
- Implementation: See `src/services/session-bootstrap-enforcer/index.ts`
- Testing: See `tests/unit/session-bootstrap-enforcer/bootstrap.spec.ts`
- Design: See ADR in parent epic #751

### Issues
- File issue in #756 (this epic)
- Tag @kushin77 for code-server bootstrap questions
- Tag @security for privilege enforcement questions

### Related
- **#740**: Policy bundle verification (dependency)
- **#751**: Core code-server transformation (parent epic)
- **#753**: Tenant-aware profiles (next in sequence)

---

*Last Updated: April 18, 2026*  
*Status: ✅ READY FOR INTEGRATION TESTING (Phase 2)*
