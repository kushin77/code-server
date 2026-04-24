## Update: Let's Encrypt Rate Limit Identified - Automatic Recovery Pending

### Root Cause (Confirmed)
**Let's Encrypt Rate Limiting** on automatic certificate renewal. Server issued 5 certificates for `ide.kushnir.cloud` in the last 7 days, hitting the strict limit (5 certs/domain/week).

### Rate Limit Details
- **Limit**: 5 certificates per exact domain per 168 hours  
- **Status**: BLOCKED - All ACME requests return HTTP 429
- **Expires**: 2026-04-25 11:35:25 UTC (approximately 27 hours from issue detection)
- **Affected domains**: ide.kushnir.cloud, kushnir.cloud, *.kushnir.cloud

### Why Health Endpoint Unreachable
1. Certificate renewal blocked by rate limit (HTTP 429)
2. Caddy has no valid certificate to present
3. TLS handshake fails with "internal error" alert  
4. DAST scanner receives SSL error, cannot proceed
5. Health endpoint returns tlsv1 alert, not HTTP response

### The Fix (Automatic)
**No manual intervention needed.** When rate limit expires (Apr 25 11:35 UTC):
- Caddy automatically retries certificate renewal
- Let's Encrypt allows new issuance
- Certificate provisioned within minutes
- DAST scanner regains connectivity
- Issue auto-resolves

### Prevention (Next Sprint)
- Implement DNS-01 challenges (DNS-based, more flexible)
- Add ACME rate limit monitoring (alert at 80% usage)  
- Use on-demand cert provisioning (lazy-load, reduce renewals)
- Batch deployments to reduce restart frequency

### Timeline
- **Now**: Both replicas awaiting auto-recovery via rate limit expiration
- **Apr 25 11:35 UTC**: Rate limit window closes, cert renewal succeeds
- **Apr 25 12:00 UTC**: Health endpoint responds normally with valid cert
- **Expected closure**: When next DAST scan runs successfully

### Documentation
- Root cause analysis: ISSUE-1686-ROOT-CAUSE-ANALYSIS.md  
- Detailed resolution plan: ISSUE-1686-RESOLUTION-PLAN.md
- Monitoring procedures included in resolution plan
