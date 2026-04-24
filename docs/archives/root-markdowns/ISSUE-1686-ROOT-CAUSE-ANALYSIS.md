# Issue #1686 — Root Cause Analysis & Fix Strategy

**Issue**: [SECURITY][zap-dast] DAST target unreachable in https://ide.kushnir.cloud/health:0  
**Status**: Root cause identified  
**Severity**: P1

---

## Root Cause

**Let's Encrypt and ZeroSSL Rate Limiting on Certificate Renewal**

Caddy logs show repeated certificate acquisition failures:

### Error 1: Let's Encrypt Rate Limit (Blocking)
```
HTTP 429 urn:ietf:params:acme:error:rateLimited - too many certificates (5) already issued 
for this exact set of identifiers in the last 168h0m0s, retry after 2026-04-25 11:35:25 UTC
```

**Meaning**: We've issued 5 certificates in the last 7 days for `ide.kushnir.cloud`. The rate limit is 5 per domain per week. Further issuance blocked until 2026-04-25 @ 11:35:25 UTC.

### Error 2: ZeroSSL Rate Limit (Fallback Blocked)
```
HTTP 429: too_many_eab_credentials_created_today (code 2904)
```

**Meaning**: ZeroSSL (fallback issuer) is also rate-limited on EAB (External Account Binding) credential creation.

### Error 3: ACME Challenge Solver Mismatch
```
no solvers available for remaining challenges (configured=[http-01 tls-alpn-01] offered=[dns-01 dns-persist-01])
```

**Meaning**: Staging Let's Encrypt expects DNS-01 challenges but Caddy is configured for HTTP-01 and TLS-ALPN-01.

---

## Impact on TLS Handshake

When Caddy cannot renew/obtain a certificate:
1. The TLS config is incomplete
2. Caddy sends a "TLS internal error" alert to clients
3. Client (ZAP scanner, curl, browsers) receives: `[SSL: TLSV1_ALERT_INTERNAL_ERROR]`
4. Connection fails before HTTP layer is reached

This explains why the health endpoint is unreachable - Caddy cannot establish TLS at all.

---

## Root Cause Chain

```
Certificate Renewal Attempt
    ↓
Rate Limit Hit (5 certs in 7 days)
    ↓
Let's Encrypt denies issuance (HTTP 429)
    ↓
ZeroSSL also rate-limited (HTTP 429)
    ↓
Staging ACME solver mismatch (no DNS-01)
    ↓
Caddy has no valid certificate to use
    ↓
TLS handshake fails with "internal error"
    ↓
DAST scanner cannot reach /health endpoint
    ↓
Issue #1686 triggered
```

---

## Solution Strategy

### Option 1: Use Existing Valid Certificate (RECOMMENDED)
- **Timeline**: Immediate
- **Action**: Check if existing certificate is still valid
- **Implementation**: Configure Caddy to use static cert instead of auto-renewal
- **Risk**: Low (certificate is already trusted)

### Option 2: Wait for Rate Limit Expiry
- **Timeline**: 2026-04-25 @ 11:35:25 UTC (~15+ hours from now)
- **Action**: Do nothing; rate limit naturally expires
- **Implementation**: Passive; Caddy will auto-retry
- **Risk**: Production blocked until then

### Option 3: Use Alternative ACME Provider
- **Timeline**: 2-4 hours (requires Caddyfile change)
- **Action**: Switch to different ACME provider without rate limit issues
- **Implementation**: Update Caddy config to use alternate issuer
- **Risk**: Medium (requires testing new issuer)

### Option 4: Suppress Certificate Renewal Temporarily
- **Timeline**: Immediate
- **Action**: Disable auto-renewal in Caddy config
- **Implementation**: Add `skip_cert_obtain` or similar directive
- **Risk**: Medium (cert expiry will create new issues later)

---

## Recommended Fix

**Use Option 1 + Document Rate Limit Prevention**

1. **Immediate** (next 15 min):
   - Configure Caddy to use existing valid certificate (static)
   - Disable auto-renewal attempts
   - Deploy to both replicas
   - Verify DAST scanner can reach /health endpoint

2. **Short-term** (after rate limit expires Apr 25 @ 11:35 UTC):
   - Re-enable auto-renewal in Caddy
   - Allow certificate refresh when rate limit lifts
   - Verify renewal succeeds

3. **Long-term** (next sprint):
   - Implement certificate renewal safeguards
   - Monitor rate limit usage
   - Implement DNS-01 challenge support for broader flexibility
   - Document rate limit prevention in ops runbook

---

## Prevention

To prevent future rate limit hits:

1. **Caddy Configuration**:
   - Use DNS-01 challenges instead of HTTP-01 (more flexible)
   - Implement `on_demand` cert provisioning (lazy loading)
   - Set renewal threshold to avoid unnecessary retries

2. **Monitoring**:
   - Alert on certificate age (renew before 60 days)
   - Alert on renewal failures (before they compound)
   - Track rate limit consumption

3. **Documentation**:
   - Document the 5-per-week rate limit
   - Document ACME provider limits in ops runbook
   - Create runbook for rate limit incident response

---

## Next Steps

1. **Triage**: Confirm existing certificate is valid and can be used
2. **Fix**: Implement static certificate configuration
3. **Deploy**: Roll out to both replicas (parallel deployment)
4. **Verify**: Confirm DAST scanner can reach endpoint
5. **Monitor**: Watch for certificate expiry
6. **Document**: Update rate limit prevention runbook

---

**Created**: April 24, 2026  
**Severity**: P1 (production TLS failure)  
**Status**: Ready for implementation
