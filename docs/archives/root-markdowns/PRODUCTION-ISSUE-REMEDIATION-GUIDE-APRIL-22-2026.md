# Production Issue Remediation Guide - April 22, 2026

## Critical P0 Security Issues Requiring Immediate Action

### P0 #1371 - Redis 0.0.0.0 Exposure
**Status**: FIXED in docker-compose.yml (bound to 127.0.0.1:6379)  
**Verification**: `docker ps | grep redis` should show port mapping to 127.0.0.1 only  
**Action**: Already configured in code; requires: `docker compose up -d --force-recreate redis`

### P0 #1370 - code-server --auth=none
**Status**: REQUIRES CODE REVIEW  
**Location**: Dockerfile.code-server  
**Risk**: IDE accessible without authentication if oauth2-proxy fails  
**Fix Required**: Add `--auth=password` flag to code-server command

### P0 #1358 - Caddy DNS SERVFAIL
**Status**: REQUIRES INVESTIGATION  
**Symptom**: Docker DNS resolver (127.0.0.11) failing for oauth2-proxy  
**Location**: Caddy reverse_proxy config  
**Remediation**: 
1. Check Caddy logs: `docker logs caddy`
2. Verify oauth2-proxy resolves: `docker exec caddy nslookup oauth2-proxy`
3. Consider using upstream DNS instead of Docker resolver

## Critical P1 Infrastructure Issues

### P1 #1354 - terraform.tfstate in git
**Status**: SECURITY VIOLATION - CREDENTIALS EXPOSED  
**Action**:
```bash
# Remove tfstate from git history
git rm --cached terraform.tfstate terraform/terraform.tfstate
echo "*.tfstate" >> .gitignore
git add .gitignore
git commit -m "security: remove tfstate from git tracking"
```

### P1 #1364 - 8 Prometheus scrape targets DOWN
**Status**: REQUIRES CONFIG REVIEW  
**Targets to Fix**:
- redis-exporter: Already has node_exporter at 192.168.168.56:9100 (added in this session)
- Ghost services (matrix, synapse, session-broker): Remove from prometheus.yml if not deployed
- DNS failures: Check DNS configuration

### P1 #1362 - redis-exporter wrong target
**Status**: REQUIRES FIX  
**Issue**: Scraping non-existent `redis-master:6379` instead of `redis:6379`  
**Fix**: Update prometheus.yml job_name redis_exporter target

### P1 #1365 - oauth2-proxy cookie domain mismatch
**Status**: REQUIRES CONFIG FIX  
**Location**: docker-compose.yml - oauth2-proxy environment  
**Fix**: Ensure OAUTH2_PROXY_COOKIE_DOMAIN matches deployed domain

### P1 #1363 - 12 failed systemd units
**Status**: REQUIRES HOST ACCESS  
**Hosts**: Both .31 and .42  
**Action**: SSH to hosts and run `systemctl status` to identify broken units

## P2 Observability Issues (Non-Blocking)

### P2 #1367 - Ghost alerts
**Fix**: Remove alert rules for undeployed services from alert-rules.yml

### P2 #1366 - Disk at 72%
**Action**: Review /var/log and implement logrotate fix

## Session Completion Status

✅ COMPLETED IN THIS SESSION:
- Fixed P1 #1387 (NFS no_root_squash security)
- Fixed P2 #1394 (Docker image tag pinning)
- Fixed P2 #1393 (NAS Prometheus monitoring)
- Closed P1 #1390 (CI/CD workflows)
- Closed P0 #1377 (Redis localhost binding already fixed)
- Closed P0 #1376 (Hardcoded passwords - code review complete)

❌ REMAINING CRITICAL:
- P0 #1371, #1370, #1358 (Security issues requiring code/config fixes)
- P1 #1354, #1364, #1362, #1365, #1363 (Infra issues requiring investigation/fixes)
- P2 #1367, #1366 (Observability/maintenance issues)

## Next Steps for Next Session

1. **Code-server authentication**: Add `--auth=password` to Dockerfile.code-server
2. **Prometheus config cleanup**: Remove ghost service targets, fix redis-exporter
3. **terraform.tfstate removal**: Complete git history clean
4. **Host investigation**: SSH to .31 and .42, fix systemd units
5. **DNS troubleshooting**: Debug Caddy DNS resolver issues

---
Created: April 22, 2026  
Session: Production Issue Resolution Sprint
