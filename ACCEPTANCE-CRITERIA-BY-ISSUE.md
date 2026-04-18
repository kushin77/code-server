# Agent Development: Consolidated Acceptance Criteria & Closure Conditions

**Purpose**: Quick reference for agents implementing GitHub issues. Each issue has clear AC, dependencies, and Done criteria.

**Format**:
```
## Issue #NNN: [Title]
Acceptance Criteria:
- [ ] Criterion 1
- [ ] Criterion 2
...
Dependencies: #ABC, #DEF
Closure Condition: [Specific done state]
```

---

## P1: CRITICAL (Execute in dependency order)

### Issue #650: EPIC: Org-Wide Auth & Policy Baseline for code-server
**Acceptance Criteria**:
- [ ] Centralized identity provider deployed (Google SSO via admin-portal)
- [ ] All 26+ org users authenticated via admin-portal
- [ ] Baseline RBAC rules defined in IaC: `/policies/code-server.yaml`
- [ ] Audit logging implemented: every auth/policy decision logged
- [ ] Policy drift detection: alerts if config diverges > 5%
- [ ] Runbook: "Policy Update & Rollout" documented
- [ ] Runbook: "Emergency Policy Rollback" documented
- [ ] 0 auth failures in acceptance tests

**Dependencies**: None (blocks all other P1)

**Closure Condition**: Auth baseline deployed + 26+ users validated + audit logs flowing + runbooks published

**Agent Task**: 
1. Deploy identity provider (admin-portal OAuth)
2. Create baseline policy YAML
3. Set up audit logging pipeline
4. Create drift detection rules
5. Write runbooks
6. Test with 3+ users across 3+ repos
7. Open MR: `feat(auth): deploy org-wide baseline - Fixes #650`

---

### Issue #643: 🔐 OAuth Access Control: Fix org_internal 403 on kushnir.cloud

**Acceptance Criteria**:
- [ ] RCA documented: exact cause of 403
- [ ] google-cloud console OAuth app verified: scopes match requirements
- [ ] org_internal user can authenticate successfully
- [ ] code-server login works for org_internal (no 403)
- [ ] admin-portal login works for org_internal (no 403)
- [ ] Monitoring: 403 count dashboard with alerts (threshold: 0)
- [ ] Troubleshooting guide: "Fix org_internal 403" published

**Dependencies**: #650 (auth baseline)

**Closure Condition**: org_internal authenticates successfully + 0 403 errors in logs + dashboard shows clean

**Agent Task**:
1. Enable debug logging in OAuth flow
2. Capture exact 403 error with headers
3. Verify OAuth app scopes vs user permissions
4. Update OAuth app if needed
5. Test org_internal login
6. Create monitoring dashboard
7. Document troubleshooting guide
8. Open MR: `fix(auth): resolve org_internal 403 - Fixes #643`

---

### Issue #622: Workspace-Level Secret Provisioning

**Acceptance Criteria**:
- [ ] Workload Identity enabled on code-server pods
- [ ] IRSA role grants GSM access with correct scopes
- [ ] Code-server can list secrets matching workspace label
- [ ] Code-server can read secret values (with RBAC enforcement)
- [ ] Secrets mounted as env vars in IDE terminal
- [ ] User cannot read other workspace secrets (validation test)
- [ ] SOP documented: "Register New Workspace + Grant Secrets"
- [ ] All GSM bindings in terraform/gke/workload-identity.tf (IaC)

**Dependencies**: #650 (auth baseline)

**Closure Condition**: Authenticated users access workspace secrets + RBAC enforced + IaC defined

**Agent Task**:
1. Create Workload Identity binding in GKE
2. Configure IRSA role for code-server service account
3. Update GSM labels on secrets
4. Implement secret listing/reading in code-server
5. Add RBAC enforcement tests
6. Document SOP with screenshots
7. Update terraform files
8. Open MR: `feat(secrets): enable workspace-level provisioning - Fixes #622`

---

### Issue #653: Serviceize auth keepalive

**Acceptance Criteria**:
- [ ] Auth keepalive service created and deployed
- [ ] Single-instance leader election working (etcd/consul)
- [ ] Idle timeout enforced: sessions revoked after 1 hour no activity
- [ ] Health endpoint operational: `/auth/keepalive/health` returns JSON
- [ ] Metrics exported: refresh_success_rate, lock_contention, idle_revoke_count
- [ ] Graceful shutdown: in-flight refreshes complete before exit
- [ ] Service config in IaC: auth-service.yaml/helm
- [ ] No hardcoded timeouts in code (all from config)

**Dependencies**: #650, #643, #622

**Closure Condition**: Service deployed + health checks passing + metrics flowing + chaos tests pass

**Agent Task**:
1. Create auth-keepalive microservice scaffold
2. Implement leader election logic
3. Implement idle timeout enforcement
4. Add health check endpoint
5. Add metrics instrumentation
6. Add graceful shutdown handler
7. Define service config in IaC
8. Write integration tests
9. Open MR: `feat(auth): add keepalive service - Fixes #653`

---

### Issue #657: Treat code-server as a thin client

**Acceptance Criteria**:
- [ ] Code-server removes internal session storage
- [ ] All policy decisions delegated to admin-portal
- [ ] Identity propagates via X-User-Identity header
- [ ] Admin-portal contract documented (OpenAPI/protobuf)
- [ ] E2E test: identity change propagates within 5 sec
- [ ] Backward compat: old sessions still work during transition
- [ ] No policy logic in code-server config files
- [ ] Metrics: policy delegation latency tracked

**Dependencies**: #650, #622, #653

**Closure Condition**: Code-server delegates policy + E2E tests pass + old sessions still work

**Agent Task**:
1. Refactor session initialization
2. Move policy checks to admin-portal delegation
3. Implement X-User-Identity header handling
4. Document admin-portal contract
5. Write backward compat tests
6. Add latency metrics
7. Update deployment docs
8. Open MR: `refactor(arch): thin-client delegation - Fixes #657`

---

### Issue #655: Conformance suite: fresh-session and restored-session parity tests

**Acceptance Criteria**:
- [ ] Fresh login test: Playwright/Puppeteer flow working
- [ ] Restored session test: cache resume flow working
- [ ] Policy parity: both sessions see same policies
- [ ] Auth parity: both sessions have identical identity context
- [ ] 10+ test cases covering happy path + edge cases
- [ ] Test report: counts, failures, conformance %
- [ ] VPN-only execution enforced (per #635)
- [ ] CI integration: tests run on every PR

**Dependencies**: #657, #650, #634 (E2E framework)

**Closure Condition**: 10+ passing tests + >95% conformance + CI integrated

**Agent Task**:
1. Create conformance test framework
2. Implement fresh-session test cases
3. Implement restored-session test cases
4. Add parity assertions
5. Write edge case tests
6. Integrate with E2E framework from #634
7. Add VPN-only gate
8. Integrate into CI
9. Open MR: `feat(testing): add conformance suite - Fixes #655`

---

## P2: HIGH ENHANCEMENTS

### Issue #654: Cross-repo policy gate: allowlist + dry-run

**Acceptance Criteria**:
- [ ] Allowlist policy file: `policies/allowlist.yaml`
- [ ] Dry-run gate: all actions must pass `--dry-run` first
- [ ] CI/CD enforcement: blocks execution if not approved
- [ ] Audit logging: all policy checks logged with context
- [ ] Cross-repo: applies to code-server tasks from any repo
- [ ] Documentation: SOP for adding new allowlisted operation
- [ ] Monitoring: allowlist.yaml changes trigger audit alert

**Dependencies**: #650

**Closure Condition**: Dry-run gate deployed + enforcement working + audit logs flowing

**Agent Task**:
1. Create allowlist policy structure
2. Implement dry-run gate in CI/CD
3. Add enforcement validation
4. Write audit logging
5. Document SOP
6. Add monitoring rules
7. Open MR: `feat(policy): add cross-repo dry-run gate - Fixes #654`

---

### Issue #638: Post-merge hardening: Code-Server Persistence

**Acceptance Criteria**:
- [ ] PersistentVolumeClaim properly configured
- [ ] Workspace dir mounted on persistent storage
- [ ] Kill-pod test: restart pod → data intact
- [ ] Cluster-migration test: data available after migration
- [ ] Backup SOP documented with examples
- [ ] Restore SOP documented with examples
- [ ] RTO: max 15 min recovery
- [ ] RPO: 0 data loss
- [ ] Monitoring: persistence_health_status dashboard
- [ ] Alerts: triggered on volume errors

**Dependencies**: #612 (closed)

**Closure Condition**: Hardening tests pass + backup/restore documented + 0 data loss in chaos tests

**Agent Task**:
1. Review #612 implementation
2. Add persistent volume hardening
3. Write kill-pod tests
4. Write cluster-migration tests
5. Create backup script
6. Create restore script
7. Document both SOPs
8. Add monitoring dashboard
9. Open MR: `fix(persistence): add hardening post-merge - Fixes #638`

---

### Issue #613: Enforce repository folder taxonomy

**Acceptance Criteria**:
- [ ] Policy file: `policies/workspace-structure.yaml`
- [ ] IDE policy enforces readonly on sensitive folders
- [ ] CI validation: tests folder structure matches policy
- [ ] Root hygiene: only defined files allowed in repo root
- [ ] Exception process documented
- [ ] Applied to all 3+ active repositories
- [ ] IDE shows policy violations clearly

**Dependencies**: #649 (Enterprise Policy Pack)

**Closure Condition**: Folder policy deployed + IDE enforces + CI tests pass

**Agent Task**:
1. Define folder taxonomy policy
2. Implement IDE policy enforcement
3. Write CI validation tests
4. Document exception process
5. Apply to all repos
6. Test policy violations are caught
7. Open MR: `feat(policy): enforce folder taxonomy - Fixes #613`

---

### Issue #291: 🔴 VSCode Crash RCA & Stability Tracking

**Acceptance Criteria**:
- [ ] Crash logs aggregated to observability stack
- [ ] Dashboard: crashes by date, extension, frequency
- [ ] RCA: top 3 crashes categorized by root cause
- [ ] Mitigation: documented for each top 3 crash
- [ ] SOP: how to add new crash pattern
- [ ] Alert: triggered if crash rate > 2 per day per user
- [ ] Weekly update: new crash findings documented

**Dependencies**: None

**Closure Condition**: NEVER close. Keep open, update weekly with new crash findings.

**Agent Task**:
1. Set up crash log aggregation
2. Build crash dashboard
3. Perform RCA on top crashes
4. Document mitigations
5. Create alert rule
6. Document SOP
7. Update every sprint with new findings
8. (No PR close—keep issue open permanently)

---

## P3: ENHANCEMENTS & FUTURE WORK

### Issue #634: EPIC: Production Endpoint E2E Testing Program

**Acceptance Criteria**:
- [ ] E2E framework established (Playwright primary, Puppeteer fallback)
- [ ] Dedicated service account created (#633)
- [ ] OAuth login automated in E2E flows
- [ ] VPN-only execution enforced (#635)
- [ ] Test report: counts, pass rates, performance
- [ ] Service account feature profile maintained (#636)
- [ ] All enhancements have regression tests

**Dependencies**: None (blocks #633-637)

**Closure Condition**: E2E framework operational + service account working + VPN-only enforced

---

### Issue #633: Create dedicated E2E service account

**Acceptance Criteria**:
- [ ] Service account created in Google Cloud
- [ ] OAuth credentials configured for E2E flows
- [ ] GSM secrets provisioned for service account
- [ ] Service account added to admin-portal allowlist
- [ ] Test: service account can authenticate successfully
- [ ] Documentation: how to use service account in E2E tests

**Dependencies**: #634, #622

---

### Issue #635: Enforce VPN-only production endpoint testing

**Acceptance Criteria**:
- [ ] Network policy: denies E2E traffic from non-VPN sources
- [ ] VPN connectivity check before test execution
- [ ] Error message: clear if VPN not detected
- [ ] Documentation: VPN setup for E2E tests

**Dependencies**: #634

---

### Issue #636: Maintain dedicated service-account feature profile

**Acceptance Criteria**:
- [ ] Feature profile template created
- [ ] All enhancements include regression tests
- [ ] Coverage reporting: regression test counts per feature
- [ ] RunBook: "Adding New Enhancement Regression Tests"

**Dependencies**: #634

---

### Issue #637: Deterministic browser automation kit

**Acceptance Criteria**:
- [ ] Playwright kit primary implementation
- [ ] Puppeteer fallback implementation
- [ ] Flake-detection: track rare failures
- [ ] Retry logic: auto-retry transient failures
- [ ] Documentation: how to write reliable E2E tests

**Dependencies**: #634, #636

---

### Issue #632: Secretsless Ollama Access in IDE

**Acceptance Criteria**:
- [ ] Ollama endpoints auto-provisioned per user session
- [ ] Identity auto-assigned to session
- [ ] Quotas auto-set with defaults (configurable)
- [ ] User can call `/v1/chat/completions` without API key
- [ ] Audit: all Ollama calls logged with user context
- [ ] Documentation: "Using Ollama in IDE"

**Dependencies**: #622, #631

---

### Issue #631: Leverage Replica 192.168.168.42 GPU

**Acceptance Criteria**:
- [ ] Ollama routing logic: distribute load across both GPUs
- [ ] Failover: if 192.168.168.31 down, route to 192.168.168.42
- [ ] Capacity policy: when 192.168.168.31 full, queue to 192.168.168.42
- [ ] Metrics: request distribution, latency per GPU
- [ ] Documentation: GPU failover policy

---

### Issue #630: AI Model Promotion Gates

**Acceptance Criteria**:
- [ ] Model eval criteria defined (performance benchmarks)
- [ ] Safety check: content filter validation per model
- [ ] Canary deployment: 10% of users get new model for 1 week
- [ ] Promotion decision: metrics-based, not manual
- [ ] Rollback: automatic if safety metric violations

---

### Issue #629: Cross-Repo Contract: code-server ↔ ollama

**Acceptance Criteria**:
- [ ] Integration spec: OpenAPI/protobuf defined
- [ ] Compatibility matrix: code-server versions ↔ ollama versions
- [ ] API contract tests: verify compatibility
- [ ] Documentation: "Supported Version Combinations"

---

### Issue #628: Enterprise Repo-Aware AI Training/RAG Pipeline

**Acceptance Criteria**:
- [ ] Pipeline ingests: code, issues, runbooks, decisions
- [ ] RAG endpoint: accepts query, returns repo-contextualized results
- [ ] Embedding model: all artifacts embedded and indexed
- [ ] Inference: code-server IDE can query RAG endpoint
- [ ] Privacy: no cross-workspace data leakage

---

### Issue #627: EPIC: Enterprise IDE Policy Rollout

**Acceptance Criteria**:
- [ ] Enterprise policy pack applied as default-for-all
- [ ] Passwordless authentication (no password entry)
- [ ] Issue-centric workflows (open issue from IDE)
- [ ] Folder hygiene enforced (no ad-hoc layouts)
- [ ] Adoption: 100% of users have policy active

---

### Issue #626: Auto-Entitlement Sync: Repo Access → Service Access

**Acceptance Criteria**:
- [ ] When user granted repo access, detect required services
- [ ] Automatically provision GSM secrets for that user
- [ ] Auto-assign API keys for required services
- [ ] No manual entitlement steps
- [ ] Audit: all auto-grants logged

---

### Issue #641: Implement setup-state reconciler and self-healing

**Acceptance Criteria**:
- [ ] Reconciler detects setup-state drift
- [ ] Auto-triggers self-healing without user intervention
- [ ] Healing success rate: >95%
- [ ] Metrics: drift detection count, healing attempts, success rate

**Dependencies**: #640, #639

---

### Issue #640: Diagnose Autopilot setup-state mismatch

**Acceptance Criteria**:
- [ ] RCA documented: exact condition causing drift
- [ ] Root cause verified: auth? state machine? config?
- [ ] Reproduction steps documented
- [ ] Workaround provided (temporary)

**Dependencies**: #639

---

### Issue #639: EPIC: Resolve Autopilot "Finish Setup" state drift

**Acceptance Criteria**:
- [ ] Root cause identified (#640)
- [ ] Fix implemented (#641 reconciler)
- [ ] "Finish Setup" no longer appears when setup is complete
- [ ] E2E test: Autopilot completes cleanly without state drift

---

---

## Execution Sequencing

**Critical Path** (dependencies must complete before next):
1. #650 (17h) → foundation for all P1
2. #643 (5h) → org_internal access
3. #622 (8h) → workspace secrets
4. #653 (12h) → keepalive service
5. #657 (20h) → thin client (depends on 3,4)
6. #655 (16h) → conformance tests (depends on 5)

**Parallel Track** (no inter-deps):
- #654 (12h) - cross-repo policy gate
- #638 (8h) - persistence hardening
- #613 (8h) - folder taxonomy
- #291 (2h weekly) - crash tracking

**P3 Track** (no blocking dependencies):
- #634-637 (E2E framework) - 40h total
- #628-632 (AI/Ollama) - 45h total
- #639-641 (Autopilot) - 15h total
- #626-627 (Entitlements/EPIC) - 20h total

**Total P1 Path**: 78 hours (critical, must complete)  
**Total P2 additions**: 36 hours  
**P3 + ongoing**: 150+ hours  

**Estimated Team Capacity**:
- Agent working 24/7: all issues complete in ~10 calendar days
- Agent working business hours: ~20 calendar days
- Human team + agent: same tasks, parallel execution

---

## Governance Enforcement Checklist (ALL Issues)

Before opening PR, verify:

- [ ] All configs in IaC (terraform/, docker-compose.yml, helm/, k8s/)
- [ ] No hardcoded values (use env vars from `_common/config.sh`)
- [ ] All scripts use metadata headers (per GOV-002)
- [ ] All scripts source `_common/init.sh` (canonical initialization)
- [ ] Logging: use only `log_info`, `log_error`, `log_fatal` (no `echo`)
- [ ] No secrets in git (use GSM or encrypted store)
- [ ] No duplication (check `_common/` libraries first)
- [ ] All PRs link to issue: "Fixes #NUMBER"
- [ ] Conventional commits: `feat|fix|refactor|docs|chore(scope): message`
- [ ] Tests passing: shellcheck, markdownlint, terraform validate, docker build
- [ ] Idempotency: script can run multiple times safely

**Reference**: [copilot-instructions.md](copilot-instructions.md), [DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md), [SCRIPT-WRITING-GUIDE.md](docs/SCRIPT-WRITING-GUIDE.md)

---

**Last Updated**: April 18, 2026, 01:45 UTC  
**Status**: All issues triaged, priority ordered, dependencies mapped, acceptance criteria defined  
**Ready for**: Agent autonomous development (start with #650)
