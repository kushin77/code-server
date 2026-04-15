# Phase 5: DNS & OAuth Configuration Playbook
**Date**: April 15, 2026 | **Status**: Ready for Immediate Execution

## Prerequisites Verified ✅
- Production infrastructure: 10/10 services healthy
- Primary host: 192.168.168.31 (SSH access confirmed)
- Domain infrastructure: ide.elevatediq.ai configured
- IaC: Consolidated and immutable
- Zero blockers for Phase 5 execution

## Phase 5a: DNS Configuration (10 minutes)

### Objective
Configure Cloudflare DNS CNAME record to route ide.elevatediq.ai through Cloudflare Tunnel

### Steps
1. **Access Cloudflare Dashboard**
   - URL: https://dash.cloudflare.com/
   - Login with organization account
   - Select domain: elevatediq.ai

2. **Add CNAME Record**
   `
   Name:    ide
   Type:    CNAME
   Content: <cloudflare-tunnel-cname>
   Proxy:   Proxied (orange cloud)
   TTL:     Auto
   `

3. **Verify DNS Resolution**
   `ash
   ssh akushnir@192.168.168.31
   nslookup ide.elevatediq.ai
   # Should resolve to Cloudflare edge IP
   `

### Expected Result
`
ide.elevatediq.ai CNAME <tunnel-cname>
Status: Proxied (orange cloud)
DNS: Propagated globally
`

---

## Phase 5b: OAuth Credential Injection (5 minutes)

### Objective
Inject real Google OAuth credentials into oauth2-proxy environment

### Prerequisites
- Google Cloud Project with OAuth 2.0 credentials configured
- Client ID and Client Secret obtained from GCP Console
- Redirect URI: https://ide.elevatediq.ai/oauth2/callback

### Steps
1. **SSH to Production Host**
   `ash
   ssh akushnir@192.168.168.31
   cd ~/code-server-enterprise
   `

2. **Update .env with Real Credentials**
   `ash
   cat >> ~/.env << 'EOF'
   GOOGLE_CLIENT_ID=<your-client-id>
   GOOGLE_CLIENT_SECRET=<your-client-secret>
   GOOGLE_ADMIN_EMAIL=<your-admin-email>
   OAUTH_REDIRECT_URI=https://ide.elevatediq.ai/oauth2/callback
   EOF
   `

3. **Restart OAuth2-proxy Service**
   `ash
   docker-compose restart oauth2-proxy
   # Wait 5 seconds for service to restart
   sleep 5
   # Verify status
   docker logs oauth2-proxy | tail -5
   `

### Verification
`ash
# Should see no cookie_secret errors
docker logs oauth2-proxy 2>&1 | grep -i "error\|cookie\|oidc"
# Should show successful OIDC initialization
docker logs oauth2-proxy 2>&1 | grep -i "oidc\|ready"
`

---

## Phase 5c: End-to-End Validation (15 minutes)

### Test 1: DNS Resolution
`ash
nslookup ide.elevatediq.ai
# Should resolve (either to CF IP or direct IP depending on tunnel status)
`

### Test 2: TLS Certificate Verification
`ash
curl -I https://ide.elevatediq.ai/
# Should return 200 or 302 (redirect to OAuth)
# Should show valid certificate
`

### Test 3: OAuth Login Flow
`ash
# Via browser: https://ide.elevatediq.ai
# Should redirect to Google OAuth login
# After authentication, should redirect to IDE
`

### Test 4: Service Health (All 10 Services)
`ash
ssh akushnir@192.168.168.31
docker ps --format 'table {{.Names}}\t{{.Status}}'
# All should show "Up (healthy)"
`

### Test 5: Monitoring Dashboards
`
Prometheus: http://192.168.168.31:9090
Grafana:    http://192.168.168.31:3001 (admin/admin123)
Jaeger:     http://192.168.168.31:16686
AlertManager: http://192.168.168.31:9093
`

---

## Success Criteria (ALL MUST PASS)

✅ DNS resolves ide.elevatediq.ai  
✅ TLS certificate valid and trusted  
✅ OAuth2-proxy initialized without errors  
✅ Google OAuth redirect working  
✅ Code-server accessible post-OAuth  
✅ All 10 services healthy  
✅ Monitoring dashboards operational  
✅ <30 second OAuth login flow  

---

## Rollback Plan (If Issues Arise)

**Revert OAuth Credentials**
`ash
ssh akushnir@192.168.168.31
# Remove problematic credentials from .env
vi ~/.env
# Remove GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
docker-compose restart oauth2-proxy
`

**Revert DNS**
`
Cloudflare Dashboard → Remove CNAME record
Re-add IP record if needed
`

---

## Post-Phase-5 Status
- **Domain**: ide.elevatediq.ai (domain-only access, OAuth protected)
- **Services**: 10/10 operational and monitored
- **Security**: Real OAuth credentials active
- **Access**: Authenticated users only
- **Monitoring**: All dashboards live
- **Status**: PRODUCTION READY FOR FULL DEPLOYMENT

---

## Immediate Next Actions (Choose One)

### Option A: Execute Immediately (Recommended)
1. SSH: ssh akushnir@192.168.168.31
2. Update .env with real Google credentials
3. Restart oauth2-proxy: docker-compose restart oauth2-proxy
4. Verify: docker logs oauth2-proxy | tail -10
5. Configure Cloudflare DNS (if tunnel not already set)

### Option B: Wait for DNS Setup
1. Configure Cloudflare DNS first
2. Then update OAuth credentials
3. Then run validation tests

### Option C: Dry Run (No Credentials)
1. Execute DNS setup only
2. Test domain resolution
3. Inject credentials once validated

---

**Phase 5 Execution Timeline**: 30 minutes total  
**Blockers**: None  
**Status**: Ready to Execute  
