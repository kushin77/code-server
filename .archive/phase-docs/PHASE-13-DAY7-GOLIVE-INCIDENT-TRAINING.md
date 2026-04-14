# Phase 13 Day 7: Production Go-Live & Incident Training
**Issue #208 - P0 Priority**
**Scheduled**: April 20, 2026
**Duration**: 8 hours (09:00 UTC - 17:00 UTC)

---

## 🎯 MASTER OBJECTIVE

Activate full production traffic migration to code-server infrastructure and conduct comprehensive incident response training for on-call teams. Validate all SLO targets continue to be met under real-world production load.

---

## 📋 DAY 7 EXECUTION TIMELINE

### Phase A: Pre-Activation (09:00 - 10:00 UTC) - 1 Hour

#### 09:00 - 09:15 UTC: Team Assembly & System Check
**Owner**: Incident Commander (akushnir)

- [ ] All teams online on #phase-13-execution Slack
- [ ] Infrastructure health check (all 6 containers running)
- [ ] Monitoring dashboards active and displaying metrics
- [ ] Incident response team on standby
- [ ] Communication channels verified (Slack, email, paging)

**Success Criteria**:
- 100% team attendance in video call
- All health checks green (6/6 containers)
- Monitoring metrics flowing in real-time
- No infrastructure alerts

**Rollback Point**: If any health check fails, abort and investigate

---

#### 09:15 - 10:00 UTC: Pre-Activation Checklist
**Owner**: DevOps Lead

- [ ] DNS failover tested (rehearsal traffic switch)
- [ ] CDN cache cleared and ready
- [ ] Database connections verified
- [ ] SSL certificates valid (expires >30 days)
- [ ] Firewall rules configured
- [ ] Rate limiting policies active
- [ ] Load balancer configuration confirmed

**Success Criteria**:
- All 7 items checked and verified
- No DNS resolution issues
- SSL/TLS handshake successful
- Rate limiting policies in place

**Commands**:
```bash
ssh akushnir@192.168.168.31
# Verify DNS
nslookup code-server.internal

# Verify SSL
openssl s_client -connect code-server.internal:443 -showcerts

# Verify load balancer
curl -vI https://code-server.internal/health
```

---

### Phase B: Production Traffic Activation (10:00 - 12:00 UTC) - 2 Hours

#### 10:00 - 10:15 UTC: Canary Activation (5% Traffic)
**Owner**: DevOps Lead

- [ ] Route 5% of production traffic to code-server
- [ ] Monitor error rate and latency for 5 minutes
- [ ] Verify SLOs are holding (p99 <100ms, error <0.1%)
- [ ] Check for upstream/downstream issues

**Success Criteria**:
- p99 latency <100ms
- Error rate <0.1%
- No "500" errors from application
- No connection timeouts

**Rollback Condition**: If error rate >1% or p99 >500ms, ROLLBACK immediately

```bash
# Check metrics
ssh akushnir@192.168.168.31 "curl http://localhost:9090/metrics | grep -E 'http_request_duration_seconds|http_request_total'"
```

---

#### 10:15 - 10:45 UTC: Graduated Canary (25% Traffic)
**Owner**: Performance Lead

- [ ] Increase traffic to 25%
- [ ] Monitor for 20 minutes continuously
- [ ] Check database connection pool utilization
- [ ] Verify cache hit ratio (target >80%)
- [ ] Monitor memory and CPU on all containers

**Success Criteria**:
- All SLOs still met (p99 <100ms, error <0.1%)
- Database pool utilization <70%
- Cache hit ratio >80%
- CPU utilization <60%
- Memory utilization <70%

**Escalation Threshold**:
- p99 latency exceeds 200ms → Investigate database
- Error rate exceeds 0.5% → Check application logs
- Memory utilization >80% → Trigger memory profiler

---

#### 10:45 - 11:30 UTC: Heavy Canary (50% Traffic)
**Owner**: Operations Lead

- [ ] Increase traffic to 50%
- [ ] Run 30-minute continuous load profile
- [ ] Simulate "busy hour" traffic patterns
- [ ] Monitor all infrastructure for bottlenecks

**Success Criteria**:
- p99 latency <150ms (still under 100ms target)
- Error rate <0.1%
- Throughput >150 req/s sustained
- All containers stable (no restarts)
- No memory leaks detected

**Rollback Decision Point**: If any metric deteriorates 3+ standard deviations from baseline, prepare rollback

---

#### 11:30 - 12:00 UTC: Full Production Activation (100% Traffic)
**Owner**: Incident Commander

- [ ] Route 100% of production traffic to code-server
- [ ] Verify all traffic successfully migrated
- [ ] Monitor for anomalies vs canary phases
- [ ] Declare production activation complete

**Success Criteria**:
- 100% traffic successfully routed
- No client connection errors
- SLOs met across all metrics
- No increase in latency vs 50% canary phase
- All teams confirm "green" status

**Command**:
```bash
ssh akushnir@192.168.168.31 "docker exec caddy caddy config show | grep -A5 upstream"
```

---

### Phase C: Incident Response Training (13:00 - 17:00 UTC) - 4 Hours

#### 13:00 - 13:30 UTC: Incident Types & Response Flowchart
**Owner**: SRE Lead

**Scenario 1: High Error Rate (>1%)**
```
1. Alert fires: Error rate exceeded 1%
2. Immediate: Open war room on Slack #incident-page
3. Diagnosis: Check application logs for errors
4. Action:
   - If application bug → Engage development team
   - If database issue → Check connection pool
   - If infrastructure → Check container status
5. Mitigation: If unresolvable in 5 min → ROLLBACK
6. Communication: Update status page every 2 minutes
```

**Scenario 2: High Latency (p99 >200ms)**
```
1. Alert fires: p99 latency exceeded 200ms
2. Immediate: Check database query performance
3. Diagnosis: Query slowlog, cache hit ratio
4. Action:
   - If slow query → Enable query optimization
   - If cache miss spike → Investigate query pattern
   - If connection bottleneck → Scale database connections
5. Mitigation: If cannot resolve → Scale horizontally or ROLLBACK
6. Escalate: If >10min → Escalate to VP Engineering
```

**Scenario 3: Container Restart Loop**
```
1. Alert fires: Container restarted 3+ times
2. Immediate: Check container logs
3. Diagnosis: Look for OOMkilled, segfaults, panic
4. Action:
   - If memory issue → Increase container limits
   - If crash loop → Investigate application logs
   - If infrastructure → Check host resources
5. Mitigation: Isolate container, drain connections, restart controlled
6. Escalate: If infrastructure → Infrastructure team
```

---

#### 13:30 - 14:30 UTC: Chaos Engineering - Controlled Failure Scenarios

**SCENARIO 1: Degrade Single Container (1 hour)**
- Reduce one container's resources to 50%
- Monitor system behavior
- Verify other containers compensate
- Test auto-scaling triggers
- Document failure mode

**SCENARIO 2: Simulate Database Slowness**
- Inject 500ms latency to database queries
- Verify circuit breaker trips
- Check error rates and client impact
- Test timeout handling
- Verify graceful degradation

**SCENARIO 3: Network Partition**
- Simulate 20% packet loss
- Monitor how system handles retries
- Check for timeout cascades
- Verify health check mechanisms
- Test reconnection behavior

---

#### 14:30 - 15:30 UTC: Live Incident Simulation

**Simulated Incident: "Accidental Database Migration"**

Scenario: Database suddenly becomes slow (database team is doing maintenance)

**What Teams Should Do**:
1. **Operations** (3 min): Detect elevated p99 latency (500ms+)
2. **SRE** (2 min): Identify database as source
3. **Database Team** (on call): Confirm maintenance in progress
4. **Product** (1 min): Assess customer impact
5. **Incident Commander** (2 min): Decide on fallback to read replicas vs. wait
6. **DevOps** (5 min): Execute fallback if needed (failover to read replica)
7. **Communication** (ongoing): Update status page every 2 minutes

**Scoring**:
- Detection <5 min: ✅ PASS
- Root cause identified <8 min: ✅ PASS
- Customer communication <10 min: ✅ PASS
- Mitigation executed <15 min: ✅ PASS
- Recovery time <20 min: ✅ PASS

---

#### 15:30 - 16:15 UTC: On-Call Rotation & Handoff

**Owner**: Operations Lead

- [ ] Establish 24/7 on-call rotation
- [ ] Confirm all on-call team members have:
  - [ ] PagerDuty access
  - [ ] SSH keys configured
  - [ ] Slack notifications enabled
  - [ ] Incident runbooks downloaded
  - [ ] Escalation contacts saved

**On-Call Schedule Template**:
```
Week 1 (Apr 21-27):  [Developer 1] Primary, [SRE 1] Secondary
Week 2 (Apr 28-May4): [Developer 2] Primary, [SRE 2] Secondary
Week 3 (May 5-11):   [Developer 3] Primary, [SRE 1] Secondary
```

**Escalation Tree**:
1. On-Call Developer (1st level)
2. On-Call SRE (2nd level)
3. Platform Lead (3rd level)
4. VP Engineering (4th level - 30 min+ incidents only)

---

#### 16:15 - 17:00 UTC: Production Turnover & Sign-Off

**Owner**: Incident Commander

- [ ] All teams acknowledge production is their responsibility
- [ ] Runbooks confirmed accessible
- [ ] Monitoring dashboards configured
- [ ] Incident response drills scheduled for future
- [ ] Sign-off from all team leads

**Final Checklist**:
- [ ] Production metrics baseline documented
- [ ] Alerting thresholds set and tested
- [ ] On-call team confirmed aware
- [ ] 24/7 support staffing in place
- [ ] Post-incident review process established
- [ ] Executive notifications configured

---

## ⚠️ CRITICAL THRESHOLDS & ACTIONS

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| p99 Latency | >150ms | >300ms | Investigate; Prepare rollback if >500ms |
| Error Rate | >0.5% | >2% | Page on-call; Prepare rollback if >5% |
| Throughput | <80 req/s | <50 req/s | Check connectivity; Consider rollback |
| Container Restart | >1 in 5min | >3 in 5min | Isolate container; Investigate logs |
| CPU/Container | >70% | >85% | Monitor closely; Prepare to scale |
| Memory/Container | >75% | >90% | Check for leaks; Prepare to restart |

---

## 🚨 ROLLBACK PROCEDURES

### Immediate Rollback (< 5 minutes)
**Command**: Execute on 192.168.168.31
```bash
ssh akushnir@192.168.168.31
cd ~/code-server-phase13
bash scripts/phase-14-rollback.sh
```

### Expected Impact**:
- Traffic diverted away from code-server
- All clients reconnect to previous infrastructure
- Recovery time: ~2-3 minutes
- Data consistency: Maintained (no writes during migration)

### Post-Rollback**:
- [ ] Run root cause analysis
- [ ] Fix identified issues
- [ ] Retry Phase 13 Day 7 (next opportunity)
- [ ] Update post-incident review

---

## 📞 CONTACT INFORMATION

**Primary Contacts**:
- Incident Commander: akushnir@company.internal
- SRE Lead: sre-lead@company.internal
- DevOps Lead: devops-lead@company.internal
- VP Engineering: vp-eng@company.internal

**Slack Channels**:
- #code-server-production (announcements)
- #incident-page (active incidents)
- #phase-13-execution (phase coordination)

**PagerDuty**: https://pagerduty.company.internal/oncall

---

## 📊 SUCCESS CRITERIA

### ✅ PASS (Go-Live Successful)
- [ ] All 4 canary phases complete without issues
- [ ] 100% traffic successfully migrated
- [ ] All SLOs met throughout activation
- [ ] Zero container crashes
- [ ] Incident response training completed
- [ ] On-call team confirmed ready
- [ ] Post-incident runbooks updated

### ❌ FAIL (Rollback Required)
- [ ] Error rate exceeds 2% at any point
- [ ] p99 latency exceeds 500ms
- [ ] Container restart loop detected
- [ ] Database connectivity issues unresolved
- [ ] Any critical vulnerability found
- [ ] Customer complaints >5 reports

---

## 📝 APPROVAL & SIGN-OFF

**Execution Authority**: VP Engineering
**Incident Command Authority**: akushnir
**SRE Authority**: SRE Lead
**Security Authority**: Security Lead

**Approval Date**: April 18, 2026 (2 days pre-execution)
**Scheduled Execution**: April 20, 2026, 09:00 UTC
**Estimated Duration**: 8 hours (09:00-17:00 UTC)

---

**Next Milestone**: Phase 15-18 Infrastructure Expansion (May 2026+)
