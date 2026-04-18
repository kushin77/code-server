# Upstream Code-Server Fork & Sync Operating Model

**Issue**: #673 - Define upstream fork/sync operating model for code-server  
**Status**: Closed with evidence  
**Date**: 2026-04-18

## Executive Summary

Code-server is deployed as a managed fork of the upstream code-server project. This document defines the operational model for maintaining sync with upstream while developing downstream enhancements.

## Model Overview

### Three-Track System

```
upstream (code-server/code-server)
    ↓
    └─→ sync gate (validation against our contract)
        ↓
origin/main (kushin77/code-server)
    ↓
    ├─→ feat/enhancement branches (downstream features)
    │   └─→ CI: Enhancement validation + upstream compatibility
    │
    └─→ production (active-active .31/.42)
```

### Ownership Boundaries

| Component | Owner | Sync Policy |
|-----------|-------|-------------|
| VSCode Core (extensions API, UI framework) | upstream | Read-only; track for API changes only |
| Code-server Runtime (CLI, config, server) | upstream | Eager sync; merge upstream updates within 1 sprint |
| Extensions (agent-farm, ollama-chat, etc) | downstream | Our repository; no upstream constraint |
| Infrastructure (terraform, docker, k8s) | downstream | Our repository; no upstream constraint |
| AI Governance (policies, access control) | downstream | Our repository; no upstream constraint |

### Dependency Directions

```
Allowed flows:
  downstream enhancements → upstream APIs (consume)
  downstream infra ← upstream server (depend on)
  
Denied flows:
  upstream core ← downstream enhancements (no backporting)
  downstream contract ← upstream policy changes (we override)
```

## Sync Frequency & Mechanics

### Weekly Sync Cycle
1. **Monday 00:00 UTC**: Automated job triggers `fetch upstream/main`
2. **Tuesday 08:00 UTC**: Engineer reviews upstream changes (daily digest)
3. **Wednesday 12:00 UTC**: If no blockers, merge upstream into origin/develop
4. **Thursday**: Contract validation gate runs (see below)
5. **Friday**: If passing, escalate merge to origin/main for release train

### Sync Validation Gate

Before merging upstream, the following contract tests must pass:

```bash
# Core workflows that must survive upstream sync
pnpm test:contract:extensions  # Our extensions load and initialize
pnpm test:contract:settings    # Settings persistence works
pnpm test:contract:auth        # OIDC auth flow unchanged
pnpm test:contract:accessibility  # A11y tree and keyboard navigation  
pnpm test:contract:terminal    # Terminal multiplexing works
```

**Contract Failure = Defer Sync**: If any contract test fails, defer upstream merge until fix lands.

## Enhancement Branching Strategy

### Two-Track CI for Every PR

```
feat/enhancement-X branch
    ├─ Track 1: Downstream Enhancement Tests
    │  └─ Test in isolation (our features + current upstream)
    │
    └─ Track 2: Upstream Compatibility Tests
       └─ Test against latest upstream/main (without our features)
          └─ Ensures upstream changes do not break our control plane
```

### Evidence Requirements for Enhancement Closure

Every enhancement PR must show:
1. **Green on enhancement track**: Feature works with current upstream
2. **Green on compatibility track**: Latest upstream passes all contracts (or documented exception)
3. **No upstream merge conflicts**: Can auto-merge upstream without manual resolution

### Example Decision Tree

```
Did upstream change VFS layer?
  ├─ YES → Run contract tests + manual review → May defer enhancement until sync complete
  └─ NO → Enhancement can proceed in parallel
```

## Ownership & Escalation

| Decision | Owner | Escalation |
|----------|-------|------------|
| Defer upstream sync due to contract failure | Engineering lead | CTO (>2 week deferral) |
| Accept downstream enhancement that conflicts with upstream roadmap | Engineering lead | Product (strategic alignment) |
| Pin outdated upstream version | CTO | Executive (risk/security trade-off) |

## Runbook: Weekly Upstream Sync

### Step 1: Fetch & Review
```bash
git fetch upstream
git log upstream/main..origin/main --format='%h %s' | head -20
```

**Approval gate**: Engineering lead reviews commits. Look for:
- Security patches (merge ASAP)
- Breaking API changes (needs contract testing)
- UI framework updates (manual testing required)

### Step 2: Test Merge
```bash
git checkout -b temp/sync-test origin/main
git merge --no-ff upstream/main
pnpm ci
pnpm test:contract:*
```

**Approval gate**: All contract tests pass (or known exception) + no conflicts.

### Step 3: Escalate & Merge
```bash
# If approved, merge to origin/main
git checkout origin/main
git merge --no-ff temp/sync-test
git push origin main

# If deferred, document reason
# (Tracked in #673 status comments)
```

## Deviations & Overrides

### When We Override Upstream

- **OAuth/Auth**: We use Google OIDC, upstream defaults to no auth → we override
- **Extensions marketplace**: We pin to approved extensions only → we override
- **Workspace layout**: We enforce monorepo structure → we override
- **Performance SLAs**: We have stricter requirements → we override with tuning

**Detection**: All overrides are in `config/upstream-overrides.yml` (future artifact).

### When We Backport to Upstream

Rarely, but if a fix is upstream-friendly:
1. Propose PR to code-server/code-server
2. Use upstream version once merged (don't carry fork)

**Decision criterion**: "Would other downstream forks benefit?" If yes, backport.

## Escalation Flowchart

```
New upstream commit arrives
    ↓
Is it a security update?
    ├─ YES → Merge immediately, coordinate P0 redeploy
    │
    └─ NO → Does it affect our contract surface?
        ├─ YES → Run contract tests
        │  ├─ Pass → Merge to develop, schedule for release train
        │  └─ Fail → Defer, escalate to CTO if >2 weeks behind
        │
        └─ NO → Apply to develop immediately
```

## Maintenance Artifacts

- **Weekly sync digest**: Posted to #engineering Slack thread every Tuesday
- **Contract test results**: Logged in `sync-validation-YYYY-MM-DD.txt` (build artifact)
- **Upstream divergence metrics**: Tracked in Prometheus (`sync.commits_behind`, `sync.contract_test_success_rate`)
- **Status page**: Public `/status/upstream-sync` showing last sync, pending PRs, contract health

## Next Steps

- [ ] Implement automated weekly sync job (CI/CD orchestration)
- [ ] Create contract test suite for core workflows (#675)
- [ ] Document enhancement module boundaries (#676)
- [ ] Build dual-track CI validation (#674)

---

**Approval**: Product (upstream strategy) + Engineering (execution model)  
**Linked Issues**: #673, #674, #675, #676  
**Contract**: All other downstream issues depend on this model being operational.
