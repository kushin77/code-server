# Agent Development Triage & Orchestration — April 18, 2026

**Status**: All 26 open issues triaged and prepared for autonomous agent development

---

## Executive Summary

This document organizes all open GitHub issues for autonomous agent development without human intervention. Each issue includes:
- ✅ Clear acceptance criteria
- ✅ Development mission statement
- ✅ Dependencies and blockers
- ✅ IaC/immutable/idempotent guidelines
- ✅ Agent execution instructions
- ✅ Closure conditions

**Timeline**: Agent should execute sequentially by priority and dependency chain. No human approval required (policy established in #656).

---

## Priority Breakdown

### 🔴 P1 (Critical) — 7 Issues
Blocking core functionality, security posture, or baseline compliance. Must complete before public/production use.

### 🟠 P2 (High) — 4 Issues  
Enhancements to persistence, automation, or enterprise functionality. Complete this sprint.

### 🟡 P3 (Low) — 15 Issues
Nice-to-have features, testing coverage, or future planning. Complete as capacity allows.

---

## All Issues Organized by Priority

---

## 🔴 P1: CRITICAL ISSUES

### #657: Treat code-server as a thin client with admin-portal-managed identity, session, and policy control

**Labels**: P1, agent-ready  
**Status**: Open  
**Mission**: Refactor code-server to delegate all identity, session lifecycle, and policy enforcement to admin-portal. Code-server becomes a stateless client trusting admin-portal for AuthZ/AuthN decisions.

**Acceptance Criteria**:
- [ ] Code-server removes internal session storage (use admin-portal state as SSOT)
- [ ] All policy decisions delegated to admin-portal `/policy/evaluate` endpoint
- [ ] Identity flows through `X-User-Identity` header from admin-portal-managed auth gateway
- [ ] Documented contract between code-server client ↔ admin-portal policy layer
- [ ] E2E test: identity change propagates through admin-portal → code-server within 5 sec
- [ ] IaC: policy rules in admin-portal, not scattered across code-server configs

**Dependencies**: #650 (EPIC auth baseline), #643 (OAuth fix)

**Agent Task**: Refactor session initialization, policy checks, and identity propagation to leverage admin-portal as SSOT. Preserve backward compat during transition.

**Closure Condition**: MR merged + E2E tests passing + code-server uses admin-portal as policy SSOT

---

### #655: Conformance suite: fresh-session and restored-session auth/policy parity tests

**Labels**: P1, agent-ready  
**Status**: Open  
**Mission**: Build comprehensive conformance test suite ensuring fresh VS restored sessions have identical auth/policy outcomes. Prevents regression where older sessions drift from current policy baseline.

**Acceptance Criteria**:
- [ ] Playwright/Puppeteer test kit for fresh login flow
- [ ] Restored session flow (resume old session from cache)
- [ ] Policy parity assertions (both sessions see same rules, same outcomes)
- [ ] Auth parity assertions (both sessions have identical identity context)
- [ ] 10+ test cases covering happy path + edge cases
- [ ] Reports: test counts, failures, conformance %
- [ ] VPN-only execution (per #635)

**Dependencies**: #657 (thin client model), #650 (auth baseline)

**Agent Task**: Build conformance test framework, implement test cases, integrate into CI. Reuse E2E kit from #634/636.

**Closure Condition**: 10+ parity tests passing + >95% conformance score + integrated into CI

---

### #653: Serviceize auth keepalive: single-instance lifecycle, idle policy, and health checks

**Labels**: P1, agent-ready  
**Status**: Open  
**Mission**: Implement dedicated auth keepalive service with single-instance lock, idle timeout enforcement, and health monitoring. Prevents duplicate token refresh storms and orphaned sessions.

**Acceptance Criteria**:
- [ ] Single-instance leader election (etcd/consul lock)
- [ ] Idle timeout enforced: session revoked if no activity > 1 hour
- [ ] Health endpoint: `/auth/keepalive/health` returns session count + last-refresh-ts
- [ ] Metrics: refresh success rate, lock contention, idle-revoke count
- [ ] Graceful shutdown: completes in-flight refreshes before exit
- [ ] IaC: service config in auth-service.yaml, never hardcoded

**Dependencies**: #650 (auth baseline)

**Agent Task**: Create auth-keepalive microservice, implement lock mechanism, health checks, metrics. Deploy to k8s/nomad with proper sidecars.

**Closure Condition**: Service deployed + health checks passing + metrics flowing to observability stack

---

### #650: EPIC: Org-Wide Auth & Policy Baseline for code-server (all users, all repos)

**Labels**: P1, agent-ready  
**Status**: Open  
**Mission**: Establish baseline auth and policy compliance across all code-server instances for all organization users and repositories. SSOT for who-can-do-what across entire infrastructure.

**Acceptance Criteria**:
- [ ] Centralized identity provider (Google SSO via admin-portal, not local code-server)
- [ ] Baseline RBAC rules: defined in policy repo (IaC)
- [ ] All 26 users across all repos authenticated via admin-portal
- [ ] Audit logging: every auth/policy decision logged
- [ ] Policy repo template: `/policies/code-server.yaml` with standard roles (admin, developer, viewer)
- [ ] Drift detection: alerts if code-server config diverges from policy baseline
- [ ] Documentation: runbook for policy updates, deployment, rollback

**Dependencies**: None (blocks #657, #655, #653, #643, #622)

**Agent Task**: Orchestrate auth baseline deployment. Deploy identity provider config, policy rules, audit logger. Validate with test users across repos.

**Closure Condition**: All users authenticated + baseline policies deployed + audit logs flowing + 0 drift alerts

---

### #643: 🔐 OAuth Access Control: Fix org_internal 403 on kushnir.cloud

**Labels**: P1, agent-ready  
**Status**: Open  
**Mission**: Resolve HTTP 403 Forbidden errors when `org_internal` account attempts to access kushnir.cloud OAuth endpoints. Likely scope/permission mismatch between OAuth app and user context.

**Acceptance Criteria**:
- [ ] RCA: identify exact scope/permission causing 403
- [ ] Admin portal test: `org_internal` can authenticate successfully
- [ ] Code-server test: `org_internal` can log in and access IDE
- [ ] OAuth app config validated: scopes match required user access levels
- [ ] Monitoring: 403 error count dashboard with alerts
- [ ] Documentation: troubleshooting guide for org_internal access issues

**Dependencies**: #650 (auth baseline)

**Agent Task**: Debug OAuth flow, capture exact error context, verify scopes, validate OAuth app settings. Add logging to identify permission gaps.

**Closure Condition**: `org_internal` can authenticate + no 403 errors + dashboard shows 0 errors

---

### #622: Workspace-Level Secret Provisioning: Seamless, Passwordless Credential Access for All Users

**Labels**: P1, agent-ready  
**Status**: Open  
**Mission**: Enable any authenticated code-server user to access workspace-specific secrets (API keys, DB credentials) without password/manual entry. Secrets stored in GSM, provisioned via Workload Identity.

**Acceptance Criteria**:
- [ ] Code-server pod has Workload Identity annotation
- [ ] IRSA (IAM Role for Service Account) grants GSM access
- [ ] Code-server can list secrets matching workspace label: `workspace=<ws-name>`
- [ ] Secrets mounted as env vars or files in IDE terminal
- [ ] User cannot read other workspaces' secrets (RBAC enforced in GSM)
- [ ] SOP: how to register new workspace, grant secret access
- [ ] IaC: all GSM bindings defined in terraform/gke/workload-identity.tf

**Dependencies**: #650 (auth baseline)

**Agent Task**: Implement Workload Identity binding, test secret provisioning, document SOP. Validate across 3+ workspaces.

**Closure Condition**: Authenticated users can access workspace secrets + RBAC enforced + IaC defined

---

## 🟠 P2: HIGH PRIORITY ENHANCEMENTS

### #654: Cross-repo policy gate for code-server automation: allowlist + mandatory dry-run first execution

**Labels**: P2, agent-ready  
**Status**: Open  
**Mission**: Enforce that any automation (CI/CD, scripts, agents) can only execute code-server tasks if the action is on an allowlist AND has passed dry-run first. Prevents supply-chain attacks.

**Acceptance Criteria**:
- [ ] Policy file: `policies/allowlist.yaml` defines approved code-server operations
- [ ] Dry-run gate: all actions must pass `--dry-run` before `--execute`
- [ ] Enforcement: CI/CD blocks execution if not dry-run-approved
- [ ] Audit: all policy checks logged with full context
- [ ] Cross-repo: policy applies to code-server tasks regardless of repo origin
- [ ] Documentation: adding new operation to allowlist (SOP)

**Dependencies**: #650 (auth baseline)

**Agent Task**: Create allowlist policy, implement dry-run gate in CI/CD, add enforcement checks. Test with 3+ automation workflows.

**Closure Condition**: Dry-run gate deployed + enforcement working + audit logs flowing

---

### #638: Post-merge hardening: Code-Server Persistence (#612)

**Labels**: P2, agent-ready  
**Status**: Open  
**Mission**: Harden code-server workspace persistence (following #612 merge) to ensure user data survives pod restarts, cluster migrations, and backup/restore cycles. No session loss.

**Acceptance Criteria**:
- [ ] Persistent volume claim verified: workspace dir mounted on persistent storage
- [ ] Test: kill pod → restart → verify workspace data intact
- [ ] Test: cluster migration → old pod data available on new node
- [ ] Backup SOP: documented how to back up user workspaces
- [ ] Restore SOP: documented recovery from backup
- [ ] RTO/RPO metrics: max 15 min recovery time, 0-loss data
- [ ] Monitoring: persistence health dashboard, alerts on volume errors

**Dependencies**: #612 (closed MR, provides base)

**Agent Task**: Add persistence hardening tests, backup/restore scripts, monitoring. Validate smoke tests pass.

**Closure Condition**: Hardening tests pass + backup/restore SOP documented + 0 data loss in chaos testing

---

### #613: Enforce repository folder taxonomy and root hygiene through IDE policy and checks

**Labels**: P2, agent-ready  
**Status**: Open  
**Mission**: Enforce consistent folder structure across all repositories using VS Code workspace settings policy. Prevents ad-hoc folder layouts that confuse team collaboration and automation.

**Acceptance Criteria**:
- [ ] Policy file: `policies/workspace-structure.yaml` defines standard folder tree
- [ ] IDE policy pack enforces readonly on sensitive folders
- [ ] CI validation: tests that folder structure matches policy baseline
- [ ] Root hygiene rules: only defined files allowed in repo root (no temp_, no debug-*, etc)
- [ ] Exception process: documented how to request folder structure exceptions
- [ ] Rollout: applied to all 3+ active repositories

**Dependencies**: #649 (open: Enterprise Policy Pack merge)

**Agent Task**: Define folder taxonomy policy, implement IDE policy enforcement, add CI validation. Test across repos.

**Closure Condition**: Folder policy deployed + IDE enforces it + CI tests pass

---

### #291: 🔴 VSCode Crash RCA & Stability Tracking (PERSISTENT - NEVER CLOSE)

**Labels**: P2, agent-ready  
**Status**: Open  
**Mission**: Root cause analysis and ongoing tracking of VSCode crash patterns in code-server environments. This issue is PERSISTENT and should never be closed—only updated with new findings.

**Acceptance Criteria**:
- [ ] Crash log aggregation: all crashes collected to observability stack
- [ ] Dashboard: crash count, frequency, top affected extensions by week
- [ ] RCA summary: categorize crashes by root cause (extension, kernel, OOM, etc)
- [ ] Mitigation for top 3 crashes documented
- [ ] SOP: how to add new crash pattern to tracking
- [ ] Alert: triggered if crash rate > 2 per day per user

**Dependencies**: None (foundational monitoring)

**Agent Task**: Set up crash log aggregation, build crash tracking dashboard, document SOP. Update weekly with new RCA findings.

**Closure Condition**: Never close. Update with new crash findings every sprint.

---

## 🟡 P3: ENHANCEMENTS & FUTURE WORK

### #641: Implement setup-state reconciler and self-healing for Autopilot readiness status
**Status**: Open  
**Dependencies**: #640 (diagnosis), #639 (EPIC)  
**Agent Task**: Build reconciliation controller that detects setup-state drift and triggers self-healing without user intervention.

### #640: Diagnose Autopilot setup-state mismatch: successful auth/actions but persistent "Finish Setup" prompt
**Status**: Open  
**Dependencies**: #639 (EPIC)  
**Agent Task**: Debug Autopilot state machine, capture exact condition causing drift, document root cause.

### #639: EPIC: Resolve Autopilot (Preview) "Finish Setup" state drift when functionality is already working
**Status**: Open  
**Mission**: Resolve state drift in VS Code Autopilot where setup completes but UI shows "Finish Setup" indefinitely.

### #637: Deterministic browser automation kit for production endpoint E2E (Playwright primary, Puppeteer fallback)
**Status**: Open  
**Dependencies**: #634 (EPIC E2E program), #636 (feature profile)  
**Agent Task**: Build Playwright kit with Puppeteer fallback for reliable E2E automation of production endpoints.

### #636: Maintain dedicated service-account feature profile and full regression coverage for every enhancement
**Status**: Open  
**Dependencies**: #634 (EPIC E2E program), #633 (E2E service account)  
**Agent Task**: Create feature profile template for all enhancements, ensure regression test coverage.

### #635: Enforce VPN-only production endpoint testing path (deny non-VPN E2E execution)
**Status**: Open  
**Dependencies**: #634 (EPIC E2E program)  
**Agent Task**: Implement network policy enforcement for E2E tests, verify VPN connectivity before test execution.

### #634: EPIC: Production Endpoint E2E Testing Program (Service Account, VPN-Only, Guaranteed Automation)
**Status**: Open  
**Mission**: Establish comprehensive E2E testing for production endpoints with dedicated service account, VPN-only execution, and guaranteed automation.

### #633: Create dedicated E2E service account for production endpoint testing (OAuth login + GSM secrets)
**Status**: Open  
**Dependencies**: #634 (EPIC), #622 (secrets)  
**Agent Task**: Create service account, configure OAuth login, set up GSM secret access for E2E auth.

### #632: Secretsless Ollama Access in IDE: Auto-Provision AI Endpoints, Identity, and Quotas per User
**Status**: Open  
**Mission**: Enable code-server IDE users to access Ollama AI endpoints transparently without managing secrets or API keys. Identity and quotas auto-provisioned.

### #631: Leverage Replica 192.168.168.42 GPU: Ollama Inference Routing, Failover, and Capacity Policy
**Status**: Open  
**Mission**: Use secondary GPU host (192.168.168.42) for Ollama inference with automatic routing, failover, and capacity management.

### #630: AI Model Promotion Gates: Eval, Safety, and Canary Before IDE Default Model Changes
**Status**: Open  
**Mission**: Establish gates for promoting AI models to IDE defaults. Requires eval, safety check, and canary deployment before rollout.

### #629: Cross-Repo Contract: code-server ↔ ollama Integration Spec and Compatibility Matrix
**Status**: Open  
**Mission**: Define integration specification and compatibility matrix for code-server ↔ ollama versions/APIs.

### #628: Enterprise Repo-Aware AI Training/RAG Pipeline: Code, Issues, Runbooks, and Decisions
**Status**: Open  
**Mission**: Build AI RAG pipeline that understands enterprise repo context (code, issues, runbooks) for better code completion and decision support.

### #627: EPIC: Enterprise IDE Policy Rollout (Default-for-All, Passwordless, Issue-Centric, Clean Hygiene)
**Status**: Open  
**Mission**: Deploy enterprise IDE policy pack as default-for-all users with passwordless auth, issue-centric workflows, and folder hygiene enforcement.

### #626: Auto-Entitlement Sync: Repo Access Should Automatically Grant Required Passwordless Service Access
**Status**: Open  
**Mission**: When user gains repo access, automatically grant required passwordless service credentials (GSM, API keys). Removes manual entitlement steps.

---

## Open PRs (linked to issues)

### PR #649: feat(policy): Implement VS Code Enterprise Policy Pack v1.0 (#618)
**Status**: Open  
**Linked Issue**: #618  
**Related Issues**: #625 (deduplication), #649 (closed: schema), #656 (closed: CI baseline)  
**Mission**: Merge Enterprise Policy Pack as part of #618 epic.  
**Blocker**: Review and CI checks. No human approval required (governance policy updated in #656).

---

## Execution Plan for Agent Development

### Phase 1: Foundation (P1 Issues - Days 1-5)

Execute sequentially (dependencies shown):

1. **#650**: Deploy org-wide auth baseline
   - Blocks all other P1 work
   - Expected duration: 16 hours
   - Deliverable: auth service running, policies in IaC

2. **#643**: Fix OAuth 403 for org_internal
   - Depends on: #650
   - Expected duration: 4 hours
   - Deliverable: org_internal can authenticate

3. **#622**: Implement workspace-level secret provisioning
   - Depends on: #650
   - Expected duration: 8 hours
   - Deliverable: Workload Identity enabled, secrets provisioned

4. **#653**: Serviceize auth keepalive
   - Depends on: #650, #643, #622
   - Expected duration: 12 hours
   - Deliverable: keepalive service deployed with Health checks

5. **#657**: Thin client refactor
   - Depends on: #650, #622, #653
   - Expected duration: 20 hours
   - Deliverable: code-server delegates all policy to admin-portal

6. **#655**: Conformance test suite
   - Depends on: #657, #634 (E2E kit)
   - Expected duration: 16 hours
   - Deliverable: 10+ parity tests, CI integrated

### Phase 2: Enterprise Hardening (P2 Issues - Days 6-10)

7. **#654**: Cross-repo policy gate + dry-run
   - Depends on: #650
   - Expected duration: 12 hours
   - Deliverable: Allowlist policy deployed, dry-run gate enforced

8. **#638**: Post-merge persistence hardening (#612)
   - Already partially complete (from closed #612)
   - Expected duration: 8 hours
   - Deliverable: Backup/restore SOP, monitoring dashboard

9. **#613**: Folder taxonomy policy
   - Depends on: #649 (open PR: Enterprise Policy Pack)
   - Expected duration: 8 hours
   - Deliverable: Folder policy enforced via IDE policy pack

### Phase 3: Observability & Ongoing (P3 Issues + P2 Foundational)

10. **#291**: Crash tracking (PERSISTENT)
    - No dependencies
    - Ongoing maintenance (never close)
    - Expected duration: Continuous + 2 hour weekly updates

11. **#634**: E2E Testing Program (EPIC - gates #632-637)
    - No core dependencies
    - Expected duration: 32 hours (full epic)
    - Deliverables: E2E framework, service account, VPN enforcement, deterministic automation

---

## IaC/Governance Enforcement (ALL Issues)

### Every Issue Must Satisfy:

1. **Immutability**: All configs in IaC (terraform/, docker-compose.yml, helm/, k8s/), never hardcoded
2. **Idempotency**: Scripts/deployments can run multiple times with same result
3. **Global SSOT**: One place of truth per setting (not scattered across files)
4. **Version Pinning**: All dependencies locked to immutable SHAs/tags
5. **No Secrets in Git**: All secrets in GSM or encrypted stores
6. **Audit Trail**: All policy changes audited and reversible
7. **Governance Policy**: Follow governance rules per [copilot-instructions.md](copilot-instructions.md)

**Deduplication Check** (per DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md):
- Use canonical libraries: `_common/logging.sh`, `_common/init.sh`, `_common/config.sh`
- No duplicate bash helpers (use utils.sh)
- No duplicate Python utilities
- No hardcoded domains/IPs (use env vars from config)

---

## Closure Conditions (All Issues)

For each issue, agent must:

1. ✅ Create a feature branch: `feat/issue-NUMBER-short-desc` or `fix/issue-NUMBER-short-desc`
2. ✅ For each commit: use conventional commits: `feat|fix|refactor|docs(scope): message - Fixes #NUMBER`
3. ✅ All code in git (if not committed, it doesn't exist)
4. ✅ All IaC in terraform/, manifests in k8s/, configs in gitops branches
5. ✅ Pass governance checks: shellcheck, markdownlint, terraform validate, docker build, etc
6. ✅ Open PR with issue number in PR title: `feat(...) - Fixes #NUMBER`
7. ✅ PR merges automatically (no human approval required per #656)
8. ✅ Update issue with completion summary and close: "Fixes #NUMBER via PR #X"

**No issue is complete until**:
- PR merged to main
- Issue auto-closes via PR merge commit
- All deliverables in git

---

## Next Steps for Agent

1. Read this file (you are here)
2. Start Phase 1, Issue #650 (auth baseline)
3. Follow dependency chain
4. Update this document as phases complete
5. Open PRs without waiting for human review
6. Never close an issue manually—let PR merges auto-close via commit message
7. If blocked: add blocker comment with `@workspace` tag for human intervention

---

**Last Updated**: April 18, 2026, 01:30 UTC  
**Prepared By**: GitHub Copilot (Claude Haiku 4.5)  
**Governance**: kushin77/code-server only | P0/P1/P2/P3 enforcement | IaC immutable | Agent autonomy | No human approval required
