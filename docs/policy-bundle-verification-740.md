# Policy Bundle Verification - Implementation & Rollout Guide

**Issue**: #740  
**Module**: `src/services/policy-bundle-verifier/`  
**Status**: ✅ Implementation Complete  
**Last Updated**: April 18, 2026

---

## Overview

This document describes the signed policy bundle verification system that enforces portal-authoritative policy control over code-server sessions. The implementation ensures all policy decisions originate from the admin portal with cryptographic proof of authenticity and integrity.

## Architecture

### Components

```
┌──────────────────────────────────────────────────────────────┐
│ Admin Portal (Policy Issuer)                                 │
│  - Signs policy bundles with RS256 private key              │
│  - Issues assertions at session start                        │
│  - Manages revocation status                                 │
└────────────────────────────────────┬────────────────────────┘
                                     │
                        PolicyBundle (JWT format)
                         - Signature: RS256
                         - Issuer: https://kushnir.cloud
                         - Audience: code-server
                         - TTL: 5 min + cache
                                     │
┌────────────────────────────────────▼────────────────────────┐
│ Code-Server Runtime                                          │
│  PolicyBundleVerifier                                        │
│  ├─ verify() - Full validation pipeline                     │
│  ├─ Signature verification (RS256)                          │
│  ├─ Expiry & time validation                                │
│  ├─ Identity assertion validation                           │
│  ├─ Version compatibility checks                            │
│  └─ Revocation status checks                                │
│                                                              │
│  Caching & Fail-Safe                                        │
│  ├─ Cache verified bundles (300s default)                   │
│  ├─ Fail-safe modes: deny-all, deny-mutating, read-only    │
│  └─ Graceful degradation on portal unreachable              │
└──────────────────────────────────────────────────────────────┘
```

### Policy Bundle Format (JWT-style)

```json
{
  "version": "1",
  "contract_id": "code-server-thin-client-v1",
  "issued_at": 1713429600,
  "expires_at": 1713429900,
  "signature": "eyJ...", // Base64-encoded RS256 signature
  "algorithm": "RS256",
  "issuer": "https://kushnir.cloud",
  "identity": {
    "email": "user@example.com",
    "sub": "user-123",
    "roles": ["developer"],
    "org": "kushin77",
    "iat": 1713429600,
    "exp": 1713433200
  },
  "entitlements": {
    "repos": ["https://github.com/kushin77/*"],
    "workspace_policy": "default",
    "extension_allowlist": ["ms-python.python"]
  },
  "workspace_policies": {
    "default": {
      "policy_version": "1.0",
      "policy_date": "2026-04-18T12:00:00Z",
      "repo_pattern": "github.com/kushin77/*",
      "extension_allowlist": ["ms-python.python"],
      "terminal_env": { "PATH": "/usr/bin:/bin" }
    }
  },
  "correlation_id": "audit-trace-12345"
}
```

## Implementation Details

### 1. Type System (`schema.ts`)

Defines all TypeScript interfaces:
- `PolicyBundle` - Complete signed bundle
- `IdentityAssertion` - User identity claims
- `RepositoryEntitlements` - Repo access rights
- `WorkspacePolicy` - Per-repo policy rules
- `VerificationResult` - Validation outcome
- `VerificationOptions` - Verification configuration

### 2. Signature Verification (`index.ts`)

#### RS256 Signature Validation

```typescript
// Public key fetching (JWKS or static PEM)
const publicKey = await fetchPublicKeyFromJWKS(issuer)

// JWT verification
jwt.verify(signedMessage, publicKey, {
  algorithms: ["RS256"],
  issuer: expectedIssuer,
  audience: expectedAudience,
})
```

**Critical Checks**:
- Signature must be valid RS256
- Issuer must match expected issuer
- Audience must be "code-server"
- Algorithm must be RS256 (no HS256 downgrades)

#### Expiry Validation

```typescript
const now = Math.floor(Date.now() / 1000)
const clockSkew = 30 // seconds

// Bundle must not be expired
if (now > exp + clockSkew) throw VerificationError("EXPIRED_BUNDLE")

// Bundle must not be issued in future
if (iat > now + clockSkew) throw VerificationError("NOT_YET_VALID")

// Issued-at must be before expiry
if (iat >= exp) throw VerificationError("INVALID_TIME_RANGE")
```

#### Version Compatibility

```typescript
// Reject bundles with higher major version (incompatible)
if (bundleVersion.major > localVersion.major) {
  throw VerificationError("INCOMPATIBLE_VERSION")
}

// Warn on downgrade (potential rollback attack)
if (bundleVersion < localVersion) {
  warning("Policy downgrade detected")
}
```

#### Identity Validation

```typescript
// Required fields: email, sub, roles, org, iat, exp
// Email format validation
// Roles must be non-empty array
// Sub must be stable user ID
```

### 3. Caching (`cacheBundle()`)

```typescript
verifier.cacheBundle(bundle, result, durationSeconds = 300)
// Caches verified bundle for 5 minutes by default
// Key: correlation_id or issuer:sub:iat

const cached = verifier.getCachedBundle(bundleId)
// Returns cached entry if still valid
// Returns null if expired
```

### 4. Fail-Safe Modes

When admin portal is unreachable:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `DENY_ALL` | Full lockout, no access | High-security, no cached policy |
| `DENY_MUTATING` | Read-only IDE access | Default: prevent data exfiltration |
| `READ_ONLY_CACHE` | Use cached policy | If cached policy available |

---

## Rollout Plan

### Phase 1: Development & Testing (1-2 weeks)

#### Week 1: Implementation ✅
- ✅ TypeScript types & interfaces
- ✅ Signature verification logic
- ✅ Expiry & time validation
- ✅ Version compatibility checks
- ✅ Comprehensive test suite (30+ scenarios)

#### Week 1 Deliverables
- Module: `src/services/policy-bundle-verifier/`
- Tests: `tests/unit/policy-bundle-verifier/conformance.spec.ts`
- All tests green: `npm test -- policy-bundle-verifier`

#### Week 2: Integration Testing
- [ ] Portal integration: Generate real RS256-signed bundles
- [ ] Code-server integration: Consume bundles at session start
- [ ] Load testing: Verify throughput <1ms per verification
- [ ] Revocation integration: Connect to revocation service (optional Phase 2)

### Phase 2: Staging Deployment (1 week)

#### Pre-Staging Checklist
- [ ] All development tests passing
- [ ] Code review complete (approval from 2+ reviewers)
- [ ] Security review: Signature validation, no downgrade vectors
- [ ] Documentation complete (this guide + inline code docs)

#### Staging Deployment Steps

1. **Deploy verifier module to staging**
   ```bash
   # Copy module to staging code-server instances
   rsync -av src/services/policy-bundle-verifier/ \
     staging.code-server:/opt/code-server/src/services/policy-bundle-verifier/
   ```

2. **Configure environment variables on staging**
   ```bash
   # .env on staging hosts
   POLICY_ISSUER_URL=https://staging-portal.kushnir.cloud
   POLICY_JWKS_URL=https://staging-portal.kushnir.cloud/.well-known/jwks.json
   POLICY_ALLOW_UNSIGNED=false  # Require real signatures
   POLICY_CLOCK_SKEW_SECONDS=30
   ```

3. **Enable policy verification in code-server bootstrap**
   ```typescript
   // During session init:
   const verifier = createPolicyBundleVerifier({
     expectedIssuer: process.env.POLICY_ISSUER_URL,
     expectedAudience: "code-server",
   })
   const result = await verifier.verify(bundle)
   if (!result.valid) {
     throw new Error(`Policy verification failed: ${result.errors[0].message}`)
   }
   ```

4. **Test with staging portal**
   - Login to staging code-server
   - Portal issues signed bundle
   - Code-server verifies signature and identity
   - Session starts with policy applied

5. **Monitoring & Verification**
   ```bash
   # Check logs for verification results
   docker logs code-server | grep -i "policy.*verif"
   
   # Monitor error rates
   prometheus query: rate(code_server_policy_verification_errors[5m])
   ```

#### Staging Success Criteria
- [ ] 100% of sessions verified successfully (no false failures)
- [ ] Verification time <1ms p99
- [ ] Signature validation catches invalid bundles
- [ ] Expired bundles rejected
- [ ] Version compatibility enforced
- [ ] Fail-safe mode activates on portal outage

### Phase 3: Canary Rollout to Production (2-3 days)

#### Canary (5% traffic)
```bash
# Update 1 of 20 production code-server instances
# Monitor for 4 hours before proceeding
```

#### Early Production (25% traffic)
```bash
# Update 5 of 20 instances
# Monitor for 8 hours
```

#### Full Production (100% traffic)
```bash
# Update all instances
# Full monitoring active
```

#### Production Deployment Steps

1. **Backup current config & code**
   ```bash
   ssh prod-host "cd /opt/code-server && \
     git tag backup-pre-policy-verification-$(date +%s) && \
     git push --tags"
   ```

2. **Deploy module to production**
   ```bash
   # Via standard deployment pipeline
   # Merge PR #740 → CI builds → Deploy to production
   ```

3. **Update code-server to consume verifier**
   ```typescript
   // In code-server session bootstrap:
   const policyResult = await verifyPolicyBundle(receivedBundle)
   if (!policyResult.valid) {
     // Audit the failure
     auditLog("POLICY_VERIFICATION_FAILED", { errors: policyResult.errors })
     
     // Enter fail-safe mode
     activateFailSafeMode(policyResult.errors[0].code)
   }
   ```

4. **Monitor production metrics**
   ```prometheus
   # Key metrics to watch
   code_server_policy_verification_requests_total
   code_server_policy_verification_errors_total
   code_server_policy_verification_duration_seconds
   code_server_policy_cache_hits_total
   code_server_policy_cache_misses_total
   ```

#### Production Success Criteria
- [ ] 0 false verification failures (100% of valid sessions pass)
- [ ] <0.1% of sessions hit fail-safe mode (indicates portal stability)
- [ ] Signature validation >99.99% accurate
- [ ] Verification latency <5ms p99 (including cache + network)
- [ ] No session drops due to policy validation

---

## Rollback Procedure

### Immediate Rollback (Emergency)

If production verification is causing session failures:

```bash
# 1. Disable verification in code-server
ssh prod-host "export POLICY_ALLOW_UNSIGNED=true && \
  docker-compose restart code-server"

# 2. Monitor recovery
watch 'docker logs code-server | grep -c "session_start"'

# 3. Notify team & begin investigation
gh issue create --title "[INCIDENT] Policy verification rollback" \
  --body "Sessions failing at verification step. Rolled back to unsigned mode."
```

### Planned Rollback (Production Issue)

1. **Disable verification flag**
   ```bash
   # In code-server runtime, set:
   POLICY_VERIFICATION_ENABLED=false
   ```

2. **Restart services**
   ```bash
   docker-compose restart code-server
   ```

3. **Verify sessions work**
   ```bash
   curl -k https://code-server.kushnir.cloud/health
   ```

4. **Investigate root cause**
   - Check verification errors in logs
   - Validate portal is issuing correct bundles
   - Check public key/JWKS availability
   - Check time skew between hosts

5. **Fix & redeploy**
   ```bash
   # Fix issue in PR
   git revert <commit-hash> # if needed
   # OR
   git commit -m "fix(policy-verifier): <issue>"
   git push
   # Redeploy when ready
   ```

---

## Verification Testing Scenarios

### Scenario 1: Valid Bundle
**Input**: Properly signed bundle with all required fields, valid times, compatible version  
**Expected**: Verification succeeds, session starts  
**Test**: `conformance.spec.ts` - Test 1.1

### Scenario 2: Expired Bundle
**Input**: Bundle with `expires_at` in past  
**Expected**: Verification fails with EXPIRED_BUNDLE error  
**Test**: `conformance.spec.ts` - Test 2.1

### Scenario 3: Invalid Signature
**Input**: Bundle with tampered signature  
**Expected**: Verification fails with INVALID_SIGNATURE error, session rejected  
**Test**: `conformance.spec.ts` - Scenario 2 (covered by CI suite)

### Scenario 4: Version Downgrade
**Input**: Bundle version lower than local (e.g., 0.9 vs 1.0)  
**Expected**: Verification succeeds but warning emitted, can be used with explicit override  
**Test**: `conformance.spec.ts` - Test 5.3

### Scenario 5: Incompatible Version
**Input**: Bundle version higher than local (e.g., 2.0 vs 1.0)  
**Expected**: Verification fails with INCOMPATIBLE_VERSION error  
**Test**: `conformance.spec.ts` - Test 5.4

### Scenario 6: Missing Identity Field
**Input**: Bundle missing required identity field (e.g., `sub`)  
**Expected**: Verification fails with MISSING_IDENTITY_FIELD error  
**Test**: `conformance.spec.ts` - Test 3.2

### Scenario 7: Invalid Issuer
**Input**: Bundle signed by different issuer  
**Expected**: Verification fails with INVALID_ISSUER error  
**Test**: `conformance.spec.ts` - Test 4.1

### Scenario 8: Portal Unreachable (Fail-Safe)
**Input**: Portal offline, cached bundle available  
**Expected**: Session uses cached policy, enters DENY_MUTATING mode if no cache  
**Test**: `conformance.spec.ts` - Test 7

### Scenario 9: Revocation Check
**Input**: Bundle marked as revoked in revocation service  
**Expected**: Verification fails with revocation error (Phase 2)  
**Test**: Future implementation

### Scenario 10: Multiple Errors
**Input**: Bundle with multiple issues (expired + invalid signature + wrong issuer)  
**Expected**: All errors collected in result, verification fails  
**Test**: `conformance.spec.ts` - Test 10.1

---

## Configuration Reference

### Environment Variables

```bash
# Issuer configuration
POLICY_ISSUER_URL=https://kushnir.cloud (default)
POLICY_JWKS_URL=https://kushnir.cloud/.well-known/jwks.json
POLICY_PUBLIC_KEY=-----BEGIN PUBLIC KEY-----... (alternative to JWKS)

# Signature validation
POLICY_ALLOW_UNSIGNED=false (production), true (testing only)

# Time validation
POLICY_CLOCK_SKEW_SECONDS=30 (default)

# Revocation (Phase 2)
POLICY_CHECK_REVOCATION=false (disabled by default)
POLICY_REVOCATION_URL=https://revocation.kushnir.cloud

# Cache
POLICY_CACHE_DURATION_SECONDS=300 (5 minutes default)

# Fail-safe
POLICY_FAIL_SAFE_MODE=deny-mutating (default)
POLICY_FAIL_SAFE_CACHE_TTL_SECONDS=600 (10 minutes)
```

### Runtime Configuration

```typescript
const verifier = createPolicyBundleVerifier({
  expectedIssuer: "https://kushnir.cloud",
  expectedAudience: "code-server",
  publicKey: fs.readFileSync("/etc/code-server/policy-issuer.pub", "utf8"),
  clockSkewSeconds: 30,
  allowUnsigned: false, // Production: require signatures
  checkRevocation: false, // Phase 2: enable revocation checks
  cacheDurationSeconds: 300,
})
```

---

## Monitoring & Alerting

### Key Metrics

```prometheus
# Verification success/failure
code_server_policy_verification_total{status="success|failure"}
code_server_policy_verification_errors_total{code="INVALID_SIGNATURE|EXPIRED_BUNDLE|..."}

# Performance
code_server_policy_verification_duration_seconds{quantile="0.99"}

# Caching
code_server_policy_cache_hits_total
code_server_policy_cache_misses_total
code_server_policy_cache_evictions_total

# Fail-safe
code_server_policy_fail_safe_activations_total{mode="deny-all|deny-mutating|read-only-cache"}
```

### Alert Rules

```yaml
# Critical: Signature validation disabled (security risk)
- alert: PolicyVerificationDisabled
  expr: code_server_policy_allow_unsigned == 1
  for: 5m
  annotations:
    summary: "Policy verification disabled on {{ $labels.instance }}"

# Warning: High verification failure rate
- alert: PolicyVerificationFailureRate
  expr: |
    rate(code_server_policy_verification_errors_total[5m])
    / rate(code_server_policy_verification_total[5m]) > 0.01
  for: 10m
  annotations:
    summary: "Policy verification failure rate >1% on {{ $labels.instance }}"

# Critical: Frequent fail-safe activations
- alert: HighFailSafeActivations
  expr: |
    rate(code_server_policy_fail_safe_activations_total[5m]) > 0.1
  for: 5m
  annotations:
    summary: "Fail-safe mode activated frequently on {{ $labels.instance }}"
```

---

## Known Limitations & Future Work

### Phase 1 (Complete) ✅
- [x] Signature verification (RS256)
- [x] Expiry & time validation
- [x] Version compatibility checks
- [x] Identity assertion validation
- [x] Basic caching
- [x] Comprehensive test suite

### Phase 2 (Future)
- [ ] Revocation service integration
- [ ] JWKS refresh strategy
- [ ] Performance optimizations (batch verification)
- [ ] Metrics & observability integration
- [ ] Break-glass override mechanism

### Known Gaps
1. **JWKS Refresh**: Currently static public key. Need refresh strategy.
2. **Revocation**: Placeholder only, not integrated with revocation service.
3. **Break-Glass**: No mechanism for admin override in emergencies.
4. **Rate Limiting**: No rate limits on verification API.

---

## Support & Escalation

### Questions
- Implementation: See `src/services/policy-bundle-verifier/index.ts`
- Testing: See `tests/unit/policy-bundle-verifier/conformance.spec.ts`
- Design: See ADR in parent epic #751

### Issues
- File issue in #740 (this epic)
- Tag @kushin77 for code-server policy questions
- Tag @infrastructure for JWKS/revocation integration

### Runbook Links
- Parent Epic: #751
- Blocking Epic: #735 (control-plane adoption)
- Related: #756 (portal assertion enforcement)

---

**End of Implementation Guide**

---

## Appendix: Code Example

```typescript
// Example: Using policy verifier in code-server session bootstrap

import { createPolicyBundleVerifier } from "@services/policy-bundle-verifier"

async function initializeSession(bundle: PolicyBundle) {
  // Create verifier
  const verifier = createPolicyBundleVerifier({
    expectedIssuer: process.env.POLICY_ISSUER_URL,
    expectedAudience: "code-server",
  })

  // Verify bundle
  const result = await verifier.verify(bundle)

  if (!result.valid) {
    // Audit the failure
    auditLog("POLICY_VERIFICATION_FAILED", {
      user: bundle.identity.email,
      errors: result.errors.map((e) => ({ code: e.code, message: e.message })),
      correlation_id: bundle.correlation_id,
    })

    // Determine fail-safe response
    if (result.errors.some((e) => e.code === "EXPIRED_BUNDLE")) {
      // Try to use cached policy
      const failSafe = verifier.getFailSafeContext(getCachedBundle())
      applyFailSafePolicy(failSafe)
    } else {
      // Other errors: deny access
      throw new Error(`Policy verification failed: ${result.errors[0].message}`)
    }
    return
  }

  // Cache verified bundle
  verifier.cacheBundle(bundle, result, 300)

  // Apply policy to session
  applyPolicy(result.bundle!)
  startSession(result.identity!)
}
```

---

*Last Updated: April 18, 2026*  
*Status: Ready for Staging Deployment*
