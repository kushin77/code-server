# Phase 14 Launch Day Checklist

**Date**: April 14, 2026  
**Target Time**: 8:00am - 10:00am UTC  
**Status**: READY FOR EXECUTION  

---

## Pre-Launch (8:00am - 8:15am UTC)

### Preparation & Notifications

- [ ] **8:00am**: VP Engineering approval received (email confirmation)
- [ ] **8:02am**: Notify #code-server-production Slack channel
  ```
  :rocket: PRODUCTION LAUNCH STARTING - 8:00am UTC
  Target: 50+ developers
  Duration: ~2 hours
  Status updates every 15 minutes in this channel
  ```

- [ ] **8:03am**: Notify #ops-critical escalation channel
  ```
  :warning: PRODUCTION LAUNCH IN PROGRESS
  On-call engineer: [Name]
  SRE Lead: [Name]
  Contact: [Phone/Slack]
  ```

- [ ] **8:04am**: Execute pre-flight checklist script
  ```bash
  bash scripts/phase-14-launch-activation-playbook.sh
  ```

- [ ] **8:05am-8:15am**: Final validation checks
  - [ ] SSH to 192.168.168.31 responds
  - [ ] docker ps shows 3/3 containers UP
  - [ ] curl http://localhost:8080 returns 200 OK
  - [ ] Memory available >20GB
  - [ ] Disk free >1GB
  - [ ] Network bridge phase13-net exists

---

## Launch (8:15am - 8:35am UTC)

### DNS & Access Layer

- [ ] **8:15am**: DNS update verification
  - [ ] Current DNS record points to 192.168.168.31
  - [ ] Verify from 2+ external locations: `dig code-server.example.com`
  - [ ] Expected result: A record → 192.168.168.31
  - [ ] TTL: 300 seconds (test phase) or 3600 (full)
  
- [ ] **8:18am**: Cloudflare CDN activation
  - [ ] Log into Cloudflare control panel
  - [ ] Navigate to code-server.example.com domain
  - [ ] Enable: "Cache Everything"
  - [ ] Set TTL: 3600 seconds
  - [ ] Enable: HTML/CSS/JavaScript minification
  - [ ] Enable: GZIP compression
  - [ ] Enable: DDoS protection (medium)
  
- [ ] **8:22am**: TLS/SSL verification
  - [ ] Certificate installed and valid
  - [ ] curl -v https://code-server.example.com
  - [ ] Expected: 200 OK, TLS 1.3
  - [ ] Certificate expiry: >30 days
  - [ ] Test from external IP (use VPN if firewalled)

- [ ] **8:25am**: OAuth2 verification
  - [ ] GitHub OAuth app configured
  - [ ] Client ID: [verified]
  - [ ] Client Secret: [verified]
  - [ ] Callback URL: https://code-server.example.com/auth/callback
  - [ ] Scope: user:email, read:user (minimum)

- [ ] **8:28am**: Firewall rules
  - [ ] Port 80 (HTTP) open to 0.0.0.0/0
  - [ ] Port 443 (HTTPS) open to 0.0.0.0/0
  - [ ] Port 22 (SSH) restricted to office IPs only
  - [ ] Port 3306 (MySQL, if used) internal only

- [ ] **8:32am**: Status page update
  - [ ] Update status.example.com
  - [ ] Status: "Operational - Production Live"
  - [ ] Monitoring: "All systems operational"

---

## Initial User Access (8:35am - 8:55am UTC)

### Developer Invitations (Staged)

- [ ] **8:35am**: Send batch 1 invitations (5 developers)
  - [ ] Email template prepared: "Welcome to code-server"
  - [ ] Include: Access link, onboarding guide, support contact
  - [ ] Track open rates & first logins
  - [ ] Monitor metrics for 5 min

- [ ] **8:40am**: Monitor batch 1 performance
  - [ ] Check Grafana dashboard: Executive overview
  - [ ] p99 latency: <100ms ✓
  - [ ] Error rate: <0.1% ✓
  - [ ] Throughput: stable ✓
  - [ ] No container restarts ✓

- [ ] **8:42am**: Send batch 2 invitations (20 developers)
  - [ ] Additional developers onboarded
  - [ ] Monitor metrics for 5 min
  - [ ] Check for any issues

- [ ] **8:48am**: Monitor batch 2 performance
  - [ ] p99 latency: <100ms ✓
  - [ ] Error rate: <0.1% ✓
  - [ ] Container health: all green ✓
  - [ ] Memory usage: <60% ✓

- [ ] **8:50am**: Send batch 3 invitations (50+ developers)
  - [ ] Full production rollout
  - [ ] Expect peak load within 5 minutes
  - [ ] Have on-call engineer ready for scaling

---

## Performance Verification (8:55am - 9:45am UTC)

### SLO Target Validation

- [ ] **8:55am**: 10-minute performance baseline
  - [ ] p99 Latency: < 100ms (target), currently: ???
  - [ ] Error Rate: < 0.1% (target), currently: ???
  - [ ] Throughput: > 100 req/s (target), currently: ???
  - [ ] Availability: 99.9%+ (target), currently: ???
  - [ ] Container restarts: 0 (target), currently: ???

- [ ] **9:05am**: 20-minute performance validation
  - [ ] All SLO metrics green ✓
  - [ ] No alerts triggered
  - [ ] No escalations needed
  - [ ] Developers reporting normal experience

- [ ] **9:15am**: 30-minute performance review
  - [ ] p99 latency trend: stable/improving ✓
  - [ ] Error rate: 0% ✓
  - [ ] Memory: stable, no leaks ✓
  - [ ] Network: healthy, no bottlenecks ✓

- [ ] **9:25am**: 40-minute performance confirmation
  - [ ] All metrics consistently green
  - [ ] No concerning trends
  - [ ] Ready for full handoff to operations

- [ ] **9:45am**: Final SLO validation (pre-launch confirmation)
  - [ ] p99 Latency: [measurement] < 100ms ✓
  - [ ] Error Rate: [measurement] < 0.1% ✓
  - [ ] Availability: [measurement] > 99.9% ✓
  - [ ] Container Restarts: [count] = 0 ✓
  - [ ] Developer feedback: [positive/stable]

---

## Launch Confirmation & Handoff (9:45am - 10:00am UTC)

### Final Sign-Offs

- [ ] **9:45am**: Infrastructure team sign-off
  - [ ] Name: ________________
  - [ ] Signature/initials: ________
  - [ ] Time: 9:45am UTC
  - [ ] Status: ✓ APPROVED

- [ ] **9:48am**: SRE team sign-off
  - [ ] Name: ________________
  - [ ] Signature/initials: ________
  - [ ] Time: 9:48am UTC
  - [ ] Status: ✓ APPROVED

- [ ] **9:50am**: Operations team sign-off
  - [ ] Name: ________________
  - [ ] Signature/initials: ________
  - [ ] Time: 9:50am UTC
  - [ ] Status: ✓ APPROVED

- [ ] **9:52am**: VP Engineering final confirmation
  - [ ] Name: ________________
  - [ ] Signature/initials: ________
  - [ ] Time: 9:52am UTC
  - [ ] Status: ✓ APPROVED FOR FINAL HANDOFF

### Handoff to Operations

- [ ] **9:55am**: Declare production LIVE
  - [ ] Update #code-server-production: "✓ PRODUCTION LIVE"
  - [ ] Update status.example.com: "All systems operational"
  - [ ] Send email: "code-server production launch complete"
  - [ ] Begin SLO monitoring for Week 1 metrics

- [ ] **10:00am**: Activate 24/7 operations
  - [ ] Primary on-call engineer: taking responsibility
  - [ ] SRE lead: standing by for escalation
  - [ ] Incident response team: ready
  - [ ] 4-hour checkpoint scheduled: 12:30pm UTC

---

## Post-Launch (10:00am+)

### Continuous Monitoring

- [ ] **10:00am+**: Begin 24/7 monitoring
  - [ ] Grafana dashboard active (refresh every 1 min)
  - [ ] Slack notifications: enabled
  - [ ] PagerDuty alerts: enabled
  - [ ] On-call rotation: active

- [ ] **12:30pm UTC** (first 4-hour checkpoint)
  - [ ] Check SLO metrics (all 4 hours)
  - [ ] Verify no incidents
  - [ ] Check developer feedback
  - [ ] Log in PHASE-14-OPERATIONS-LOG.md

- [ ] **4:30pm UTC** (second 8-hour checkpoint)
  - [ ] Full SLO analysis
  - [ ] Identify any trends
  - [ ] Check scaling needs

- [ ] **9:00pm UTC** (third 12-hour checkpoint)
  - [ ] Full operational review
  - [ ] Document any issues
  - [ ] Plan for Week 1 review

---

## Incident Response During Launch

**If SLO violation occurs**:

1. **Immediate Response** (T+0:00-0:01)
   - [ ] Alert triggered in PagerDuty
   - [ ] On-call engineer acknowledges
   - [ ] Open Grafana dashboard
   - [ ] Slack notification sent

2. **Investigation** (T+0:01-0:03)
   - [ ] Check container logs: `docker logs <container>`
   - [ ] Check system resources: memory, CPU, disk
   - [ ] Check network connectivity
   - [ ] Identify root cause

3. **Resolution** (T+0:03-10:00)
   - [ ] If memory issue: restart container (RTO <1s)
   - [ ] If query issue: optimize database
   - [ ] If load issue: scale horizontally
   - [ ] If auth issue: check OAuth service

4. **Verification** (T+10:00+)
   - [ ] Metrics return to normal
   - [ ] No additional errors
   - [ ] Document in incident log

**If container restart detected**:
- [ ] CRITICAL: Page on-call engineer immediately
- [ ] Check restart logs for cause
- [ ] Implement fix or rollback
- [ ] Document root cause

**If DNS/CDN issues**:
- [ ] Check DNS propagation: `dig code-server.example.com`
- [ ] Check Cloudflare status
- [ ] Failover to direct IP if needed
- [ ] Contact DNS provider if necessary

---

## Success Criteria

✅ **Launch Complete When**:
- [ ] All 6 infrastructure checks pass
- [ ] DNS resolving correctly
- [ ] HTTPS/TLS working
- [ ] OAuth2 authentication working
- [ ] p99 Latency < 100ms
- [ ] Error Rate < 0.1%
- [ ] Availability > 99.9%
- [ ] Zero container restarts
- [ ] 50+ developers successfully onboarded
- [ ] All sign-offs obtained
- [ ] Team declares launch complete

---

## Emergency Rollback (If Needed)

**Trigger**: Any critical system failure

**Procedure** (RTO <2 min):
```bash
# Step 1: Disable public DNS
# Point production domain back to dev endpoint

# Step 2: Notify users
# Send notification: "Maintenance in progress"

# Step 3: Rollback to previous version
docker-compose -f docker-compose.yml down
git checkout previous-stable-version
docker-compose -f docker-compose.yml up -d

# Step 4: Verify
curl -f http://localhost:8080

# Step 5: Resume operations or continue troubleshooting
```

---

## Launch Log

**Log File**: PHASE-14-LAUNCH-LOG.md  
**Start Time**: ______________ UTC  
**End Time**: ______________ UTC  
**Duration**: ______________ minutes  

**Key Events**:
- 8:00am: Pre-flight validation started
- 8:15am: DNS updated
- 8:25am: Cloudflare CDN activated
- 8:35am: Batch 1 invitations sent (5 dev)
- 8:42am: Batch 2 invitations sent (20 dev)
- 8:50am: Batch 3 invitations sent (50+ dev)
- 9:45am: All SLO targets met
- 10:00am: **PRODUCTION LIVE** ✓

**Issues Encountered**: _____________________

**Resolution**: ____________________________

**Team Confidence**: 5/5 ✓ EXCELLENT

---

**Checklist Owner**: ________________  
**Date**: April 14, 2026  
**Status**: READY FOR EXECUTION  

**All items marked [ ] must be completed before proceeding to next section.**
