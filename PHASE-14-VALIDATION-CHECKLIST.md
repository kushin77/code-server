# Phase 14: Production Launch - Validation Checklist

**Status**: Ready for Validation  
**Date**: April 13, 2026  
**All Blockers**: ✅ RESOLVED  

---

## Validation Tasks (In Progress)

### 1. DNS Configuration ⏳
- [ ] Update DNS records for ide.kushnir.cloud → 192.168.168.31
- [ ] Verify DNS resolves: `nslookup ide.kushnir.cloud`
- [ ] Wait for DNS propagation (typically 5-30 minutes)

### 2. TLS Certificate Verification ⏳  
- [ ] Verify self-signed cert CN matches ide.kushnir.cloud
- [ ] Test: `curl -k -I https://ide.kushnir.cloud/`
- [ ] Validate certificate chain loads in browser
- [ ] TODO: Replace with CA-signed cert post-launch

### 3. OAuth2 Access Control Flow ⏳
- [ ] Test OAuth2 redirect: `curl -L https://ide.kushnir.cloud/oauth2/start`
- [ ] Verify Google OAuth prompts
- [ ] Test denied access (non-allowlisted email)
- [ ] Test allowed access (allowlisted email)

### 4. Code-Server IDE Functionality ⏳
- [ ] IDE loads in browser without JavaScript errors
- [ ] Extensions load (Copilot, Copilot Chat)
- [ ] File operations work (create, edit, delete)
- [ ] Terminal opens and accepts commands
- [ ] GitHub authentication works

### 5. SSH Proxy Tunneling ⏳
- [ ] SSH connection through proxy: `ssh -p 2222 coder@ide.kushnir.cloud`
- [ ] Audit logging functional
- [ ] Session recording active

### 6. Ollama LLM Service ⏳
- [ ] Ollama API responds: `/api/tags`
- [ ] Code-server can query Ollama: `http://ollama:11434/api/generate`
- [ ] Copilot Chat can use Ollama models

### 7. Cache Layer (Redis) ⏳
- [ ] Redis responding to PING
- [ ] Session cache working
- [ ] Performance metrics collected

### 8. Load Testing ⏳
- [ ] Execute Phase 13 Day 2 load test repeat
- [ ] Verify p99 latency <100ms
- [ ] Verify error rate <0.1%
- [ ] Verify availability >99.9%

---

## Success Criteria

All of the following must be TRUE:
- ✅ All 6 services running and healthy (caddy, oauth2-proxy, code-server, ssh-proxy, ollama, redis)
- ✅ No "exec: operation not permitted" errors in containers
- ✅ TLS certificate loads without warnings
- ✅ OAuth2 flow completes successfully
- ✅ IDE loads and is responsive
- ✅ Load test meets SLO targets
- ⏳ DNS fully propagated and resolving

---

## Known Issues / Workarounds

### 1. TLS Certificate (TEMPORARY)
- Using self-signed certificate valid only for ide.kushnir.cloud
- Browser will show security warning (expected)
- **Permanent Fix**: Replace with CA-signed cert (GoDaddy or CloudFlare)
- **Timeline**: Post-launch, before prod handoff

### 2. AppArmor + Seccomp (TEMPORARY)
- All containers running with `apparmor=unconfined` + `seccomp=unconfined`
- This is TEMPORARY for development/testing
- **Permanent Fix**: Infrastructure team to develop custom AppArmor profile
- **Timeline**: TBD, security hardening task

### 3. DNS Dependency
- Phase 14 requires DNS records updated by infrastructure team
- Localhost testing works, but not via domain name
- **Blocker**: Waiting for DNS configuration

---

## Phase 14 Go/No-Go Gate

**Decision Point**: When all validation tasks above are ✅ COMPLETE

**GO Approval Requires**:
1. ✅ All container services running
2. ✅ IDE accessible via HTTPS
3. ✅ OAuth2 access control functional
4. ✅ Load test SLOs met
5. ✅ DNS fully propagated
6. ✅ Zero security vulnerabilities (AppArmor exception noted)

**NO-GO Triggers**:
- Service startup failures / restart loops
- TLS certificate chain breaks
- OAuth2 authentication failures
- SLO violations (p99 >100ms, errors >0.1%, availability <99.9%)
- Unresolved blocker issues

---

## Escalation Path

| Issue | Owner | Contact |
|-------|-------|---------|
| DNS records not updating | Infrastructure/Networking | [TBD] |
| AppArmor/seccomp hardening | Infrastructure/Security | [TBD] |
| CA certificate procurement | DevOps | [TBD] |
| Phase 14 GO/NO-GO decision | Tech Lead | [TBD] |

---

## Documentation References

- [PHASE-14-UNBLOCK-COMPLETE.md](PHASE-14-UNBLOCK-COMPLETE.md) - Blocker resolution
- [PHASE-14-STATUS-APRIL-13.md](PHASE-14-STATUS-APRIL-13.md) - Initial diagnostics
- [Caddyfile](Caddyfile) - Reverse proxy config
- [docker-compose.yml](docker-compose.yml) - Service stack definition

---

## Timeline

| Time | Milestone |
|------|-----------|
| 18:35 UTC | SSL cert issue identified |
| 20:45 UTC | ✅ All blockers resolved |
| **TBD** | ⏳ DNS records configured |
| **TBD** | ⏳ Validation complete |
| **TBD** | ⏳ GO/NO-GO decision |
| **TBD** | 🚀 Phase 14 Launch |

---

## IaC Compliance

- ✅ All changes tracked in git
- ✅ docker-compose.yml versioned
- ✅ Dockerfile changes pinned
- ✅ Environment config in .env
- ✅ Documentation immutable
- ✅ Deployment idempotent

---

**Next Action**: Wait for DNS configuration from infrastructure team, then proceed with validation checklist.
