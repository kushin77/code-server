# P1 #1420: DAST Scan Configuration Error - False Positive Remediation

**Issue:** [SECURITY][zap-dast] DAST target unreachable in http://127.0.0.1:1/:0  
**Severity:** P1 (security-scan)  
**Status:** FALSE POSITIVE - Scanning misconfiguration, not a vulnerability  
**Resolution:** Fix DAST configuration to use correct target

## Analysis

### Root Cause

The DAST scan (ZAP - OWASP Zed Attack Proxy) is configured with an **invalid and unreachable target**:
- **Attempted Target:** `http://127.0.0.1:1/`
- **Port:** 1 (TCP port 1 is reserved and not usable for application services)
- **Error:** `Connection refused` (ECONNREFUSED)
- **Evidence:** `<urlopen error [Errno 111] Connection refused>`

### Why This Is a False Positive

1. **Port 1 is reserved** - Cannot bind to TCP port 1 on most systems (requires root privilege and is reserved for privileged services)
2. **No application listening** - The scan fails to connect, which is expected behavior
3. **Not a security vulnerability** - This is a scan configuration error, not a code or infrastructure security issue
4. **Blocking legitimate scans** - False positives delay real security work

### Actual Application Ports

Based on repository configuration:
- **Code Server IDE:** 8443 (HTTPS), 8080 (HTTP)
- **API Gateway:** 443 (HTTPS), 80 (HTTP)
- **Redis:** 6379 (internal)
- **PostgreSQL:** 5432 (internal)
- **Prometheus:** 9090 (metrics)
- **WebSocket Gateway:** 8080 (HTTP), 8443 (HTTPS), 8404 (HAProxy stats)

## Remediation

### Fix 1: Update CI/CD Scan Configuration

**File to Update:** `.github/workflows/security.yml` or equivalent DAST job config

**Change:**
```yaml
# WRONG
dast_target_url: "http://127.0.0.1:1/"

# CORRECT
dast_target_url: "http://127.0.0.1:8080/"
# or for production
dast_target_url: "https://ide.kushnir.cloud/"
```

### Fix 2: Update ZAP Configuration

**File:** `.github/workflows/dast-zap-config.yaml` or similar

**Add proper target validation:**
```yaml
sites:
  - name: "Code Server IDE"
    url: "http://localhost:8080"
    port: 8080
    
  - name: "API Gateway"
    url: "https://localhost:443"
    port: 443
    
  - name: "WebSocket Gateway"
    url: "http://localhost:8404"
    port: 8404
```

### Fix 3: Add Pre-Scan Port Validation

**Script:** `scripts/ci/validate-dast-targets.sh`

```bash
#!/usr/bin/env bash
# Validate DAST scan targets are reachable before scanning

validate_port() {
    local host=$1
    local port=$2
    
    if timeout 2 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
        echo "✓ ${host}:${port} is reachable"
        return 0
    else
        echo "✗ ${host}:${port} is unreachable - skipping scan"
        return 1
    fi
}

# Validate all targets
validate_port "127.0.0.1" 8080 || exit 1
validate_port "127.0.0.1" 8443 || exit 1
validate_port "127.0.0.1" 8404 || exit 1

echo "All DAST targets are reachable - proceeding with scan"
```

## Impact Assessment

### Before Fix
- ❌ False positive blocking security reviews
- ❌ DAST scan configuration is broken
- ❌ Real vulnerabilities may be missed
- ❌ CI/CD pipeline flagged with security alerts

### After Fix
- ✅ Valid application ports scanned (8080, 8443, 8404)
- ✅ Actual security vulnerabilities detected
- ✅ False positives eliminated
- ✅ Legitimate security gaps identified

## Suppression vs. Fix

### Option A: Fix (Recommended)
**Effort:** 15 minutes  
**Benefit:** Enables real DAST scanning  
**Risk:** None - scanning valid ports

**Recommendation:** ✅ PROCEED WITH FIX

### Option B: Suppress
**Effort:** 5 minutes  
**Benefit:** Closes false positive  
**Risk:** Broken DAST pipeline remains unfixed

## Verification Steps

After implementing fix:

1. **Run DAST scan with corrected target:**
   ```bash
   # Start application
   docker-compose up -d
   
   # Validate target is reachable
   curl -I http://localhost:8080/health
   
   # Run ZAP scan
   zap-baseline.py -t http://localhost:8080/ -r dast-results.html
   ```

2. **Verify scan finds real issues (if any exist)**

3. **Confirm no "target unreachable" errors**

4. **Review discovered vulnerabilities (if any)**

## Security Considerations

- **No code changes required** - This is a configuration fix, not a vulnerability patch
- **No impact on application security** - False positive doesn't affect actual security posture
- **Improves security process** - Fixing DAST configuration enables better vulnerability detection
- **Port usage is documented** - All open ports are intentional and documented

## Timeline

- **Issue Created:** 2026-04-22 16:03:38Z
- **Root Cause Identified:** Scan configuration error (port 1 invalid)
- **Fix Duration:** 15 minutes
- **Deployment:** Immediate (configuration-only change)

## References

- **OWASP ZAP:** https://www.zaproxy.org/
- **Reserved Ports:** https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
- **Port 1:** Marked as reserved (TCPMUX)
- **Issue:** https://github.com/kushin77/code-server/issues/1420

## Conclusion

**P1 #1420 is a FALSE POSITIVE caused by invalid DAST scan configuration (port 1).**

**Resolution:** Update scan configuration to use valid application ports (8080, 8443, 8404).

**Action:** Close as not-a-bug with configuration fix recommendation.

---

**Status:** Ready to close  
**Recommendation:** Fix DAST configuration before re-opening security scanning  
