# Phase 14: Quick Execution Reference Card
## One-Page Launch Validation Guide

**Status**: ✅ Ready to Execute  
**Date**: April 13, 2026  
**Critical**: All tests must run FROM VPN client  

---

## STEP 1: Verify VPN Connection (5 min)

```bash
# User's local machine (on VPN):
ping -c 3 192.168.168.31      # Should all succeed <100ms
cat /etc/resolv.conf | grep nameserver  # Should show internal DNS server
```

**✅ SUCCESS**: Ping responses + VPN DNS configured

**❌ FAILURE**: Reconnect to VPN and retry

---

## STEP 2: Execute Validation Suite (15 min)

```bash
# User's local machine (on VPN):
bash /scripts/phase-14-vpn-validation-runner.sh
```

**EXPECTED OUTPUT**:
```
✅ Found: dig
✅ Found: curl
✅ Found: openssl
✅ Can reach production host (192.168.168.31)
✅ DNS validation PASSED
✅ Service health check completed
✅ Certificate CN matches domain
Results: X passed, 0 failed, 0 warnings
✅ Phase 14 VPN-Aware Validation PASSED
```

**VALIDATION LOG**: `/tmp/phase-14-vpn-validation-TIMESTAMP.log`

**✅ SUCCESS**: All tests show ✅, report shows "PASSED"

**❌ FAILURE**: See troubleshooting below

---

## STEP 3: Review Results (3 min)

```bash
# Display results summary:
tail -20 /tmp/phase-14-vpn-validation-*.log
```

**Look for**:
- ✅ DNS Resolution: 192.168.168.31
- ✅ TLS Certificate: CN matches ide.kushnir.cloud
- ✅ HTTPS Response: Status 200 or 301
- ✅ Service Health: 6/6 running

---

## STEP 4: Get Team Approvals (30 min)

**Notify**:
- [ ] Engineering Lead: Tests passed ✅
- [ ] Security Lead: Security OK ✅
- [ ] DevOps Lead: Infrastructure ready ✅

**Comment on GitHub Issue #214**:
```
Validation Results: ✅ ALL PASSED

DNS: ide.kushnir.cloud → 192.168.168.31 ✅
TLS: Certificate CN valid ✅
HTTPS: Endpoint responding ✅
Services: 6/6 healthy ✅

Ready for production launch.
```

---

## STEP 5: Go Live (10 min)

```bash
# Execute (ONLY after all approvals):
ssh akushnir@192.168.168.31 "cd /home/akushnir/code-server-phase13 && bash go-live.sh"

# Verify:
curl -kI https://ide.kushnir.cloud/    # Should return HTTP 200 or 301
```

**✅ SUCCESS**: HTTPS responds, services running

**❌ FAILURE**: Rollback and investigate

---

## STEP 6: 24-Hour Monitoring

```bash
# Every hour for 24 hours:
ssh akushnir@192.168.168.31 "docker ps" | grep -c "Up"  # Should be 6
curl -s -o /dev/null -w "%{http_code}" https://ide.kushnir.cloud/  # Should be 200/301

# Check logs hourly:
ssh akushnir@192.168.168.31 "docker logs caddy 2>&1 | grep -i error"  # Should be empty or non-critical
```

---

## Troubleshooting Quick Guide

### ❌ Ping Fails
```bash
# Not on VPN
Solution: Connect to production VPN, try again
```

### ❌ DNS Doesn't Resolve
```bash
# Check DNS servers:
dig ide.kushnir.cloud @8.8.8.8  # Try public DNS
dig ide.kushnir.cloud +trace    # Debug resolver path

# Issue: DNS propagation not complete
# Solution: Contact infrastructure team
```

### ❌ TLS Handshake Fails
```bash
# Check certificate on host:
ssh akushnir@192.168.168.31 "ls -l /home/akushnir/code-server-phase13/ssl/"

# Regenerate cert (if needed):
ssh akushnir@192.168.168.31 "openssl req -x509 -newkey rsa:2048 -keyout ssl/cf_origin.key -out ssl/cf_origin.crt -days 365 -nodes -subj '/CN=ide.kushnir.cloud'"

# Issue: Caddy not loading cert
# Solution: Check Caddy logs
```

### ❌ HTTPS Returns Error
```bash
# Check Caddy status:
ssh akushnir@192.168.168.31 "docker logs caddy | tail -50"

# Restart Caddy:
ssh akushnir@192.168.168.31 "docker-compose restart caddy"

# Issue: Service configuration
# Solution: Review Caddyfile configuration
```

### ❌ Services Not Running
```bash
# Check health:
ssh akushnir@192.168.168.31 "docker ps -a"

# Restart all:
ssh akushnir@192.168.168.31 "cd /home/akushnir/code-server-phase13 && docker-compose restart"

# Issue: Service crash or resource issue
# Solution: Contact DevOps team
```

---

## Files Reference

| File | Purpose | Location |
|------|---------|----------|
| phase-14-vpn-validation-runner.sh | Main validation orchestrator | `/scripts/` |
| phase-14-vpn-dns-validation.sh | DNS/TLS tester | `/scripts/` |
| PHASE-14-VPN-VALIDATION-CHECKLIST.md | Detailed test cases | Root |
| PHASE-14-LAUNCH-EXECUTION-PLAN.md | Complete execution plan | Root |
| PHASE-14-VPN-VALIDATION-READY.md | Readiness summary | Root |
| docker-compose.yml | Service definitions | Root |
| Caddyfile | Reverse proxy config | Root |

---

## Success Checklist

**PRE-LAUNCH**:
- [ ] User on VPN
- [ ] Validation suite passes (all ✅)
- [ ] Team permissions granted
- [ ] Rollback plan confirmed

**GO-LIVE**:
- [ ] Run go-live script
- [ ] HTTPS endpoint responds
- [ ] Services still running

**POST-LAUNCH**:
- [ ] Monitor 24 hours
- [ ] Zero critical errors
- [ ] DNS working
- [ ] TLS valid
- [ ] OAuth2 successful
- [ ] Users accessing successfully

---

## Critical Contacts

| Role | Contact |
|------|---------|
| DevOps Lead | TBD |
| Security Lead | TBD |
| Infrastructure | TBD |
| GitHub Issue | #214 |

---

## Commands Summary

```bash
# 1. Check VPN
ping 192.168.168.31

# 2. Run validation
bash /scripts/phase-14-vpn-validation-runner.sh

# 3. Review results
tail -20 /tmp/phase-14-vpn-validation-*.log

# 4. Go live
ssh akushnir@192.168.168.31 && bash go-live.sh

# 5. Verify
curl -kI https://ide.kushnir.cloud/

# 6. Monitor
ssh akushnir@192.168.168.31 && docker ps
```

---

## Quick Command Cheat Sheet

```bash
# VPN Check
ping -c 1 192.168.168.31 && echo "VPN OK" || echo "NO VPN"

# DNS Check
dig ide.kushnir.cloud A +short

# TLS Check
openssl s_client -connect ide.kushnir.cloud:443 -servername ide.kushnir.cloud </dev/null | openssl x509 -noout -subject

# HTTPS Check
curl -kI https://ide.kushnir.cloud/

# Service Check
ssh akushnir@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Log Check
ssh akushnir@192.168.168.31 "docker logs caddy"
```

---

**NEXT ACTION**: Run validation suite and report results

**TIME ESTIMATE**: 30 minutes total (5+15+3+7)

**CRITICAL**: All tests must run FROM VPN to reflect user perspective

---

*Quick Reference Card - Keep this handy during Phase 14 launch*
