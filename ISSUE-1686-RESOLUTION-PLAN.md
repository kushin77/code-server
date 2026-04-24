# Issue #1686 — Resolution Plan & Waiting Strategy

**Issue**: [SECURITY][zap-dast] DAST target unreachable in https://ide.kushnir.cloud/health:0  
**Root Cause**: Let's Encrypt rate limiting (5 certs per domain per week)  
**Detection Time**: April 24, 2026 ~08:00 UTC  
**Rate Limit Expiry**: April 25, 2026 11:35:25 UTC (approximately 27 hours from April 24 08:00 UTC)  
**Status**: Awaiting rate limit expiration

---

## Executive Summary

The DAST scanner cannot reach the health endpoint due to a TLS error. The root cause is that Caddy attempted automatic certificate renewal but hit Let's Encrypt's rate limit (5 certificates per exact domain per 7-day window). With no valid certificate available, Caddy sends a TLS internal error to all clients.

**The fix is simple: Wait for the rate limit to expire.** Caddy will automatically retry and succeed once the rate limit window closes.

**Estimated time to resolution: ~27 hours**

---

## Why This Happened

### Certificate Renewal Cycle
1. Caddy runs on production replicas with Let's Encrypt auto-provisioning
2. Certificates expire after ~90 days
3. Caddy attempts renewal ~60 days before expiry
4. Multiple deployments/restarts in the past 7 days triggered repeated renewal attempts
5. Let's Encrypt rate limit kicked in after 5 certificate issuances in the last 7 days

### Rate Limit Details
```
Let's Encrypt Limit: 5 certificates per exact set of identifiers per 7 days
Domains Affected: 
  - ide.kushnir.cloud (retry after 2026-04-25 11:35:25 UTC)
  - kushnir.cloud (retry after 2026-04-25 11:35:25 UTC)
  - *.kushnir.cloud (separate limit)

ZeroSSL Fallback: Also rate-limited (HTTP 429 on EAB creation)
```

### Why Fixes Didn't Work
Attempted fixes to bypass the rate limit:
1. ❌ `tls { on_demand }` — Still tries ACME, hits rate limit
2. ❌ `tls internal` — Invalid Caddy 2.7.6 syntax
3. ❌ Adding `skip_cert_obtain` — Not a valid Caddy directive

**Lesson**: Caddy 2.7.6 does not have a built-in way to disable ACME and use fallback certificates without modifying the code or using external certificate provisioning.

---

## Resolution Timeline

### Current (April 24, 2026)
- ✅ Root cause identified and documented
- ✅ Rate limit detection times confirmed
- 🕐 Waiting for rate limit expiration
- 📊 Both replicas synchronized and monitoring for automatic recovery

### April 25, 2026 ~11:35 UTC (Rate Limit Expiration)
- Caddy will automatically retry certificate renewal
- Let's Encrypt will allow new issuance
- Certificate will be provisioned within minutes
- DAST scanner will regain connectivity
- Health endpoint will respond with valid certificate
- **Issue will auto-resolve** ✅

---

## Monitoring During Wait Period

### Health Check
```bash
# Test endpoint reach (will fail with TLS error until rate limit expires)
curl -v https://ide.kushnir.cloud/health
# Expected error: tlsv1 alert internal error

# Monitor Caddy logs for renewal attempts
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose logs caddy | grep -i 'obtain\|429'"
```

### Automatic Recovery Confirmation
Once rate limit expires, Caddy will:
1. Retry certificate request (auto-scheduled)
2. Receive certificate from Let's Encrypt
3. Load certificate into TLS config
4. Start responding to TLS handshakes normally
5. Health endpoint becomes accessible

### Expected Log Output After Recovery
```json
{"level":"info","logger":"tls.obtain","msg":"certificate obtained successfully","identifier":"ide.kushnir.cloud"}
{"level":"info","logger":"http","msg":"server started","address":"0.0.0.0:443"}
```

---

## Prevention Strategy (Post-Recovery)

### Short-term (Next 30 days)
1. **Disable automatic certificate renewal during testing**
   - Add environment variable to Caddy: `CADDY_CERT_RENEWAL_DISABLED=true`
   - Or use `on_demand` provisioning (lazy loading)

2. **Reduce deployment frequency**
   - Batch configuration changes together
   - Avoid restarts unless necessary (would trigger renewal check)

3. **Monitor certificate age**
   - Track days until expiry
   - Alert at 60 days, 45 days, 30 days

### Long-term (Next Sprint)
1. **Implement DNS-01 challenges**
   - More flexible than HTTP-01 (doesn't require port 80 accessibility)
   - Supports wildcard certificates

2. **Use multiple ACME providers**
   - Round-robin between Let's Encrypt and ZeroSSL
   - Distribute rate limit load

3. **Implement certificate pre-caching**
   - Pre-generate certificates before deployment
   - Load from cache, fallback to ACME
   - Reduces ACME request volume

4. **Add ACME rate limit monitoring**
   - Track certificate issuance count per domain
   - Alert when approaching limits
   - Prevent over-provisioning

---

## Acceptance Criteria

This issue will be considered **RESOLVED** when:

1. ✅ Rate limit expires (2026-04-25 11:35 UTC or later)
2. ✅ Caddy automatically retries and obtains certificate
3. ✅ DAST scanner can reach health endpoint without TLS errors
4. ✅ Health endpoint responds with "OK 200"
5. ✅ HTTPS connection establishes without certificate warnings
6. ✅ Confirmation logged in GitHub issue

---

## Escalation Path (if rate limit doesn't expire as expected)

**If the issue persists past 2026-04-25 12:00 UTC**:

1. Manually provision certificate
   - Generate self-signed certificate
   - Mount into Caddy container
   - Update Caddyfile to use static cert

2. Alternative: Implement manual certificate renewal
   - Use certbot outside of Caddy
   - Copy certificate into Caddy data volume
   - Configure Caddy to use mounted certs

3. Temporary workaround: Use HTTP-only health endpoint
   - Accept TLS cert warnings
   - Allow HTTP requests to /health endpoint
   - Keep HTTPS for production traffic

---

## Issue Closure

This issue will be **automatically closed** when:
- Caddy successfully renews the certificate (expected Apr 25 11:35+ UTC)
- DAST scan runs successfully and reaches the endpoint
- No more "unable to reach" or TLS errors

**Manual closure criteria** (if auto-recovery fails):
- Implement manual certificate provisioning
- Document root cause in runbook
- Add prevention controls
- Mark as "closed-insufficient-data"

---

**Last Updated**: April 24, 2026  
**Next Check**: April 25, 2026 @ 11:30 UTC (5 min before expiry)  
**Status**: Waiting for automatic recovery via rate limit expiration
