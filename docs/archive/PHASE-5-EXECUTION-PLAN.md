# PHASE 5: POST-MERGE DNS & OAUTH SETUP
**Timeline**: 30 minutes | **Start**: Immediately after PR merge to main | **Status**: READY

---

## ✅ PREREQUISITES (ALL COMPLETE)

### Git Operations (DONE ✅)
- ✅ Tag v4.0.0-phase-4-ready created & pushed
- ✅ Feature branch feat/elite-0.01-master-consolidation-20260415-121733 ready for PR
- ✅ Production: 10/10 services healthy on 192.168.168.31

### Manual GitHub Steps (ADMIN REQUIRED - 5 min)
**NOTE**: Due to API collaborator restrictions, these require GitHub UI:

1. **Create PR via GitHub UI**
   - Go to: https://github.com/kushin77/code-server/compare/main...feat/elite-0.01-master-consolidation-20260415-121733
   - Title: `feat: ELITE Phase 4 - Infrastructure consolidation, domain migration, OAuth framework`
   - Description: Use ELITE-PHASE-4-PRODUCTION-HANDOFF.md
   - Click "Create pull request"

2. **Merge PR to main**
   - Review changes
   - Select "Squash and merge" (recommended)
   - Click "Confirm squash and merge"

3. **Close GitHub Issues** (5 issues)
   - For each: #168, #147, #163, #145, #176
   - Click "Close issue"
   - Add label "elite-delivered"

---

## 🔧 PHASE 5 EXECUTION (30 min total)

### Phase 5a: DNS Configuration (10 minutes)
**Host**: 192.168.168.31 | **Status**: Ready

**Step 1**: Cloudflare Dashboard
```
1. Log in to Cloudflare Dashboard
2. Select domain: kushnir.cloud
3. Add DNS record:
   Type: CNAME
   Name: ide
   Target: <your-tunnel-url>
   Proxied: YES (orange cloud)
4. Save
```

**Step 2**: Verify DNS Resolution
```bash
ssh akushnir@192.168.168.31
nslookup ide.kushnir.cloud
# Should resolve successfully
```

---

### Phase 5b: OAuth Credentials Setup (5 minutes)

**Step 1**: Update .env with Real GCP Credentials
```bash
ssh akushnir@192.168.168.31
cat >> ~/.env << 'ENVEND'
GOOGLE_CLIENT_ID=<your-real-client-id>
GOOGLE_CLIENT_SECRET=<your-real-client-secret>
GOOGLE_ADMIN_EMAIL=admin@yourdomain.com
ENVEND
```

**Step 2**: Restart oauth2-proxy
```bash
cd ~/code-server-enterprise
docker-compose restart oauth2-proxy
docker logs oauth2-proxy 2>&1 | tail -5
```

---

### Phase 5c: Production Validation (15 minutes)

#### Validation 1: DNS Resolution ✅
```bash
ssh akushnir@192.168.168.31
nslookup ide.kushnir.cloud
```

#### Validation 2: TLS Certificate ✅
```bash
curl -v https://ide.kushnir.cloud/ 2>&1 | head -20
```

#### Validation 3: OAuth Redirect Flow ✅
1. Open browser: https://ide.kushnir.cloud
2. Should redirect to Google login
3. Log in with Google account
4. Should redirect back to IDE
5. IDE should be accessible

#### Validation 4: Service Health ✅
```bash
ssh akushnir@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

#### Validation 5: Monitoring Dashboards ✅
- Prometheus: http://192.168.168.31:9090
- Grafana: http://192.168.168.31:3000 (admin/admin123)
- Jaeger: http://192.168.168.31:16686
- AlertManager: http://192.168.168.31:9093

---

## ✅ SUCCESS CRITERIA (ALL MUST PASS)

- [ ] DNS: ide.kushnir.cloud resolves
- [ ] TLS: Certificate is valid
- [ ] OAuth: Redirect flow works
- [ ] IDE: code-server accessible
- [ ] Services: All 10 containers healthy
- [ ] Monitoring: Prometheus/Grafana operational
- [ ] Alerting: AlertManager routing working

**Timeline**: 30 minutes from admin PR merge
**Status**: PRODUCTION-READY FOR IMMEDIATE EXECUTION

---

## 🚀 NEXT: PHASE 6 (Database Optimization)
After Phase 5 validation complete:
- Deploy pgBouncer for connection pooling
- Configure transaction pooling
- Run load tests (1x/2x/5x throughput)
- Canary rollout (1% → 100%)
- Target: 10x throughput, <100ms p99 latency

---

## 📞 SUPPORT & ROLLBACK

**If DNS Issues**:
```bash
dig ide.kushnir.cloud +short
ssh akushnir@192.168.168.31 "docker exec caddy cat /etc/caddy/Caddyfile | grep ide"
```

**If OAuth Issues**:
```bash
ssh akushnir@192.168.168.31 "docker logs oauth2-proxy 2>&1 | grep -i error"
docker-compose restart oauth2-proxy
```

**Quick Rollback** (<5 min):
```bash
git revert v4.0.0-phase-4-ready
git push origin main
```

---

**Status**: ✅ PHASE 5 READY FOR EXECUTION
**No blockers. All systems operational. Awaiting admin PR merge to start Phase 5.**
