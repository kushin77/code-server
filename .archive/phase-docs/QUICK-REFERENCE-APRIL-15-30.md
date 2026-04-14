# QUICK REFERENCE - April 15-30 EXECUTION PLAYBOOK

**Last Updated**: April 14, 2026, 19:15 UTC  
**Branch**: temp/deploy-phase-16-18  
**Deploy To**: 192.168.168.31 (primary), 192.168.168.30 (standby)

---

## 📋 KEY FILES & LOCATIONS

### IaC & Configuration
```
terraform/locals.tf                    - Single source of truth (1,200+ lines)
terraform/main.tf                      - Docker-compose resources
terraform/22b-service-mesh.tf         - Istio configuration (550 lines)
terraform/22b-caching.tf              - Varnish + rate limiting (400 lines)
terraform/22b-routing.tf              - BGP failover configuration (550 lines)
```

### Operational Procedures
```
APRIL-21-GOVERNANCE-LAUNCH-RUNBOOK.md                - Training & soft-launch (500+ lines)
PHASE-26A-RATE-LIMITING-DEPLOYMENT-PLAN.md           - Rate limiting deployment (400+ lines)
TERRAFORM-INTEGRATION-VERIFICATION-FINAL.md          - IaC audit report (500+ lines)
PHASE-COMPLETION-TRACKING-APRIL-14.md               - Phase matrix & issue triage (407 lines)
APRIL-14-EXECUTION-COMPLETION.md                    - Session summary & timeline (496 lines)
```

### Load Testing
```
load-tests/phase-26-rate-limiting.js  - k6 framework (250+ lines)
```

### Dashboards & Monitoring
```
http://192.168.168.31:9090           - Prometheus metrics
http://192.168.168.31:3000           - Grafana dashboards (admin/admin123)
http://192.168.168.31:9093           - AlertManager
http://192.168.168.31:8080           - code-server IDE
http://192.168.168.31:4000           - GraphQL API
http://192.168.168.31:3001           - Developer Portal
```

---

## 🔄 EXECUTION TIMELINE (April 15-30)

### APRIL 15 - PHASE 22-B STAGING KICKOFF
**Duration**: Full day (9:00-18:00 UTC)  
**Owner**: Infrastructure team  
**Status**: Need code review approvals  

**Checklist**:
- [ ] 09:00 Review terraform/22b-service-mesh.tf → Approve
- [ ] 10:00 Review terraform/22b-caching.tf → Approve  
- [ ] 11:00 Review terraform/22b-routing.tf → Approve
- [ ] 12:00 Prepare staging Kubernetes cluster
- [ ] 13:00 Deploy Istio to staging
- [ ] 14:00 Deploy Varnish caching layer
- [ ] 15:00 Configure BGP health checks
- [ ] 16:00 Run connectivity tests
- [ ] 17:00 Verify all services healthy
- [ ] 18:00 Update GitHub #259 with results

**Key Files to Review**:
- terraform/22b-service-mesh.tf (Istio 1.19.3 configuration)
- terraform/22b-caching.tf (Varnish 7.3 configuration)
- terraform/22b-routing.tf (VyOS 1.4 configuration)

**Success Criteria**: All services healthy in staging environment

---

### APRIL 17 - CRITICAL GATE: BRANCH PROTECTION ACTIVATION
**Duration**: 15 minutes (17:00 UTC recommended)  
**Owner**: Repository maintainer only  
**Status**: REQUIRED for April 21 governance launch  

**Procedure** (GitHub #274):
1. Log into GitHub
2. Go to: Settings → repo/kushin77/code-server → Branches → main
3. Add required status check: `validate-config.yml`
4. Enable: "Require branches to be up to date before merging"
5. Enable: "Require code review approval"
6. Save configuration
7. Test with minimal PR to verify

**Risk**: ⚠️ If NOT done by April 21, governance soft-launch BLOCKED

---

### APRIL 17-19 - PHASE 26-A: RATE LIMITING DEPLOYMENT
**Duration**: 3 days (staging → production canary)  
**Owner**: API team + DevOps  
**Status**: Load testing framework ready  

**April 17 - Staging Deployment**:
- [ ] Deploy rate limiting middleware to graphql-api (staging)
- [ ] Configure tier quotas (Free: 60/min, Pro: 1000/min, Enterprise: 10000/min)
- [ ] Setup Prometheus monitoring
- [ ] Run baseline load test (100 VUs)

**April 18 - Peak Load Testing** (See: load-tests/phase-26-rate-limiting.js):
```bash
# Run k6 test framework
k6 run load-tests/phase-26-rate-limiting.js \
  --vus 1000 --duration 10m \
  --tags rate_limiting \
  --out json=results.json
```
- [ ] Validate: >99% accuracy
- [ ] Validate: <50ms p99 latency
- [ ] Validate: <0.1% error rate
- [ ] Review metrics in Prometheus

**April 19-20 - Production Rollout**:
- [ ] Deploy to production (gradual rollout)
- [ ] Enable rate limiting for Free tier
- [ ] Monitor: X-RateLimit-* headers in responses
- [ ] Watch error rates and performance impact
- [ ] Verify cost reduction from API abuse prevention

**Expected Outcome**: Unblocks Phase 26-B SDKs (April 20+)

---

### APRIL 19-22 - PHASE 22-B: PRODUCTION CANARY DEPLOYMENT
**Duration**: 4 days (gradual traffic ramp)  
**Owner**: Infrastructure team  
**Status**: Staging validation required first (April 18)  

**April 19 - Start Canary (10% traffic)**:
- [ ] Deploy Phase 22-B infrastructure (Istio/Varnish/BGP)
- [ ] Route 10% of traffic through new infrastructure
- [ ] Monitor: latency, error rates, resource usage
- [ ] Check CloudFlare headers and tracing
- [ ] Verify: <1% error rate

**April 20 - Ramp to 20% traffic**:
- [ ] Check overnight metrics
- [ ] Increase traffic to 20%
- [ ] Monitor error budgets
- [ ] Review Grafana dashboards

**April 21 - Ramp to 50% traffic**:
- [ ] Morning metrics review
- [ ] Increase traffic to 50%
- [ ] Run health checks on both paths
- [ ] Verify: mTLS working properly

**April 22 - Full Production (100% traffic)**:
- [ ] Final metrics review
- [ ] Increase to 100% traffic
- [ ] Monitor for 2 hours (peak traffic expected)
- [ ] Close GitHub #259 issue
- [ ] Update Phase 22 status

**Success Criteria**: 
- <50ms p99 latency
- <0.5% error rate
- mTLS encryption verified
- Canary detection working

---

### APRIL 21 - PHASE 3: GOVERNANCE SOFT-LAUNCH TRAINING
**Duration**: 30 minutes (2:00 PM UTC)  
**Owner**: Platform team + all engineers  
**Status**: Training material ready (APRIL-21-GOVERNANCE-LAUNCH-RUNBOOK.md)  

**Attendees**: Full engineering team (8-12 developers)

**Agenda** (See: APRIL-21-GOVERNANCE-LAUNCH-RUNBOOK.md):
1. **Welcome & Philosophy** (5 min)
   - Why governance matters
   - MSI Code principles

2. **5 Governance Rules** (10 min)
   - Rule 1: Conventional commits (fix/feat/docs/test)
   - Rule 2: Comprehensive testing (95%+ coverage)
   - Rule 3: Security hardening (no secrets, immutable versions)
   - Rule 4: Architecture precision (scalability, resilience)
   - Rule 5: Documentation (clear, actionable for future devs)

3. **Live CI Demonstration** (5 min)
   - Show validate-config.yml running
   - Demonstrate passed checks
   - Demonstrate failed checks and fixes

4. **Q&A** (10 min)
   - Clarify governance rules
   - Address concerns
   - Align team expectations

**Post-Meeting**:
- Soft-launch period: April 21-25 (CI warns, doesn't block)
- Hard enforcement: April 28+ (CI blocks failed checks)
- Remediation: Any issues can be fixed before April 28

---

### APRIL 21-25 - PHASE 26-B: MULTI-LANGUAGE SDKs
**Duration**: 5 days  
**Owner**: SDK team  
**Status**: Unblocked by Phase 26-A completion (April 19)  

**SDK Generation**:
- [ ] Python SDK (openapi-generator)
- [ ] Go SDK (openapi-generator)
- [ ] JavaScript SDK (openapi-generator)
- [ ] Java SDK (openapi-generator)
- [ ] Rust SDK (openapi-generator)

**Distribution**:
- [ ] Publish to package repositories (PyPI, npm, Maven, crates.io)
- [ ] Generate documentation from OpenAPI spec
- [ ] Create sample code snippets
- [ ] Setup GitHub releases

**Testing**:
- [ ] Integration tests for each SDK
- [ ] Example projects for each language
- [ ] SDK documentation complete

---

### APRIL 25-27 - PHASE 26-C: ORGANIZATIONS & RBAC
**Duration**: 3 days  
**Owner**: Backend team  
**Status**: Unblocked by Phase 26-B completion (Apr 20)  

**Features**:
- [ ] Organization creation UI
- [ ] Team management
- [ ] Role-based access control (Admin/Member/Viewer)
- [ ] SSO integration (SAML/OIDC)
- [ ] Audit logging

**Testing**:
- [ ] RBAC enforcement verification
- [ ] SSO flow testing
- [ ] Multi-org isolation verification

---

### APRIL 28-30 - PHASE 26-D: WEBHOOKS & EVENTS
**Duration**: 3 days  
**Owner**: Backend team  
**Status**: Unblocked by Phase 26-C completion (Apr 27)  

**Features**:
- [ ] Event delivery system
- [ ] Webhook management UI
- [ ] Retry logic (3 retries, exponential backoff)
- [ ] Signature verification (SHA256)
- [ ] Event audit trail

**Events Supported**:
- user_created
- project_created
- api_call
- deployment
- security_event

**Phase 26 Completion**: May 1, 2026 (unblocks Phase 27)

---

## 🚨 CRITICAL GATES (Do Not Skip)

### Gate 1: April 15 - Staging Approval
- **What**: terraform/22b-*.tf files code review
- **When**: April 15, 09:00-12:00 UTC
- **Who**: 2+ senior engineers
- **Risk**: If delayed, Phase 22-B staging slips 1 day

### Gate 2: April 17 - Branch Protection Activation
- **What**: GitHub Settings → Enable validate-config.yml check
- **When**: April 17, 17:00 UTC (15-minute task)
- **Who**: Repository maintainer
- **Risk**: If missed, April 21 governance launch BLOCKED (hard stop)

### Gate 3: April 18 - Load Test Success
- **What**: k6 rate limiting tests pass (>99% accuracy)
- **When**: April 18, 14:00 UTC
- **Who**: API/DevOps team
- **Risk**: If tests fail, Phase 26-A production rollout delayed (April 22+)

### Gate 4: April 19 - Phase 22-B Canary Start
- **What**: All Phase 22-B staging tests pass, approved for canary
- **When**: April 19, 09:00 UTC
- **Who**: Infrastructure team
- **Risk**: If staging has issues, must resolve before canary (slip 1-2 days)

---

## 📊 SUCCESS METRICS

### Phase 22-B Success Criteria
- ✅ Latency p99: <50ms (must not increase)
- ✅ Error rate: <1% (production baseline)
- ✅ mTLS: 100% of connections encrypted
- ✅ Circuit breakers: Working as designed
- ✅ Canary: Traffic ramp successful

### Phase 26-A Success Criteria
- ✅ Rate limit accuracy: >99%
- ✅ Latency added: <5ms
- ✅ Header correctness: 100%
- ✅ Tier enforcement: Free/Pro/Enterprise working
- ✅ Cost impact: Reduced API abuse costs

### Governance Success (Phase 3)
- ✅ Team attendance: 100% at training
- ✅ Understanding: All team members familiar with 5 rules
- ✅ Adoption: All PRs follow conventions by May 1
- ✅ Enforcement: CI checks only warnings until Apr 28

---

## 🔗 IMPORTANT LINKS

**GitHub Issues** (Track Progress):
- Phase 22-B Advanced Networking: https://github.com/kushin77/code-server/issues/259
- Phase 25 Cost Optimization: https://github.com/kushin77/code-server/issues/264
- Phase 26 Developer Ecosystem: https://github.com/kushin77/code-server/issues/269
- April 17 Branch Protection: https://github.com/kushin77/code-server/issues/274

**Monitoring Dashboards**:
- Prometheus: http://192.168.168.31:9090
- Grafana: http://192.168.168.31:3000 (admin/admin123)
- AlertManager: http://192.168.168.31:9093

**Documentation**:
- IaC Verification Report: TERRAFORM-INTEGRATION-VERIFICATION-FINAL.md
- Governance Runbook: APRIL-21-GOVERNANCE-LAUNCH-RUNBOOK.md
- Rate Limiting Plan: PHASE-26A-RATE-LIMITING-DEPLOYMENT-PLAN.md
- Load Test Framework: load-tests/phase-26-rate-limiting.js

---

## 📞 ESCALATION CONTACTS

**Infrastructure Issues**: SSH to 192.168.168.31 (akushnir)  
**GitHub Issues**: Comment on relevant issue  
**Emergency**: Check standby host 192.168.168.30 (auto-failover ready)  

**Key Command**:
```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Check service status
docker-compose ps

# View logs
docker-compose logs -f <service_name>

# Health check
curl http://localhost:9090/-/healthy  # Prometheus
```

---

## ✅ CHECKLIST: April 15 Morning

- [ ] Read APRIL-14-EXECUTION-COMPLETION.md (session summary)
- [ ] Read TERRAFORM-INTEGRATION-VERIFICATION-FINAL.md (IaC audit)
- [ ] Review terraform/22b-service-mesh.tf (code review)
- [ ] Review terraform/22b-caching.tf (code review)
- [ ] Review terraform/22b-routing.tf (code review)
- [ ] Verify staging environment prepared
- [ ] Check Git commits pushed (e7cbbbce, eb3ff3fa, 10d99785)
- [ ] Confirm GitHub issues updated (#259, #264, #269)
- [ ] Verify Phase 25 services still healthy (docker-compose ps)
- [ ] Begin staging deployment (09:00 UTC)

---

**Status**: 🟢 **ALL SYSTEMS READY - GO FOR STAGING DEPLOYMENT**

**Session End**: April 14, 2026, 19:15 UTC  
**Next Briefing**: April 15, 09:00 UTC (Staging Kickoff)  
**Next Critical Gate**: April 17, 17:00 UTC (Branch Protection)  
**Target Completion**: May 1, 2026 (Phase 26 complete, Phase 27 unblocked)
