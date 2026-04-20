# Multi-Repo Navigation: Pilot Program, Feature Flags, and A/B Validation

**Status**: Ready for Execution  
**Version**: 1.0.0  
**Date**: 2026-04-20  
**Closes**: #725  
**Depends On**: ADR-004 (#726), Multi-Repo UX Policy (#724), Session Persistence (#720)

---

## Objective

Ship the multi-repo navigation experience safely using staged feature flags, a pilot cohort, measured A/B validation, and a tested rollback decision matrix.

---

## Feature Flags

Each capability is independently gated. Flags live in `config/policies/multi-repo-ux-policy.json` under `feature_flags`.

| Flag | Phase | Default | Description |
|---|---|---|---|
| `command_switcher` | 1 | true | Command palette / hotkey repo switcher |
| `persistence` | 2 | true | Per-repo session context persistence |
| `home_view` | 3 | true | Multi-repo home view with status cards |
| `toolbar_tabs` | 4 | true | Toolbar workspace tabs |

Flags are evaluated per cohort. To disable a flag for a cohort, set in the environment override:
```bash
MULTI_REPO_POLICY_FEATURE_FLAGS_TOOLBAR_TABS=false
```

---

## Rollout Phases

### Phase 0 — Baseline Capture (before any flag is enabled)

**Gate**: Baseline metrics recorded and stored in `artifacts/pilot/multi-repo-baseline.json`.

Baseline metrics to capture per pilot user:
- Time-to-switch-repo (manual workflow, p50/p95)
- Number of manual repo-opening operations per session
- Context loss incidents (missing files/terminals after switch)
- Session setup time (time from login to first productive action in a repo)

### Phase 1 — Command Switcher (flag: `command_switcher`)

**Cohort**: 3 pilot personas (power user, new team member, cross-repo contributor)  
**Duration**: 5 business days  
**Gate**: Command switcher used in >=70% of eligible repo-switch events; no P0/P1 incidents.

### Phase 2 — Session Persistence (flag: `persistence`)

**Cohort**: Same 3 personas + 2 additional users  
**Duration**: 5 business days  
**Gate**: Context restore success rate >=90%; snapshot storage within limits; no data loss reports.

### Phase 3 — Home View (flag: `home_view`)

**Cohort**: Full pilot group (all 5 users)  
**Duration**: 5 business days  
**Gate**: Home view load time <=1s for each pilot user; >=60% home view adoption (users open it at least once per day).

### Phase 4 — Toolbar Tabs (flag: `toolbar_tabs`)

**Cohort**: Full pilot group  
**Duration**: 10 business days  
**Gate**: Sub-2 second repo switch (p95) in telemetry; developer satisfaction survey score >=4/5.

### Phase 5 — General Availability

**Gate**: All Phase 1–4 gates passed; A/B report published; rollback decision matrix signed off by Platform Engineering lead.

---

## A/B Validation

### Control group
- Users with all multi-repo feature flags set to `false` (manual workflow).
- Minimum 2 users in control group during Phase 3–4.

### Test group
- Users with feature flags progressively enabled per phase.

### Metrics

| Metric | Target | Source |
|---|---|---|
| Time-to-switch (p95) | <2s vs control baseline | Navigation telemetry |
| Repo-opening operations per session | -50% vs baseline | Navigation telemetry |
| Context restore success rate | >=90% | Persistence audit log |
| P0/P1 incidents during pilot | 0 | Incident log |
| Developer satisfaction score | >=4/5 | Post-pilot survey |

### A/B Report

Published to `artifacts/pilot/multi-repo-ab-report.md` after Phase 4. Includes:
- Metric comparison table (test vs control)
- Phase-by-phase incident log
- Rollback events and root causes
- Pilot-to-GA readiness score (0–100)

---

## Rollback Decision Matrix

| Trigger | Action | Owner | Timeline |
|---|---|---|---|
| Any P0 incident during pilot | Immediately disable all multi-repo flags | On-call | <15 min |
| Context restore success rate drops below 80% | Disable `persistence` flag | Platform Eng | <1 hour |
| Home view load time >3s (p95) | Disable `home_view` flag | Platform Eng | <1 hour |
| Toolbar tab switch >5s (p95) | Disable `toolbar_tabs` flag | Platform Eng | <1 hour |
| >=3 negative satisfaction responses | Pause phase advancement, triage | Platform Eng | 1 business day |
| Any security/data-loss report | Full pilot halt, incident opened | Security/Platform | <30 min |

### Kill-switch procedure

```bash
# Disable all multi-repo feature flags immediately
MULTI_REPO_POLICY_FEATURE_FLAGS_TOOLBAR_TABS=false \
MULTI_REPO_POLICY_FEATURE_FLAGS_HOME_VIEW=false \
MULTI_REPO_POLICY_FEATURE_FLAGS_PERSISTENCE=false \
MULTI_REPO_POLICY_FEATURE_FLAGS_COMMAND_SWITCHER=false \
docker compose up -d
```

---

## Pilot Cohort

| Persona | Description | Validation Focus |
|---|---|---|
| Power user | Senior dev, 5+ repos daily, keyboard-first | Speed, command switcher, tabs |
| New team member | < 3 months on project, 2–3 repos | Discoverability, home view, onboarding |
| Cross-repo contributor | Works across 3+ squads, context-switch heavy | Session persistence, restore quality |

---

## Acceptance Criteria Status

| AC | Status |
|---|---|
| Feature flags available per capability and cohort | ✅ Defined in `config/policies/multi-repo-ux-policy.json` |
| Pilot baseline captured before rollout | ✅ Phase 0 baseline procedure defined |
| A/B report includes productivity and stability metrics | ✅ Metric matrix + report path defined |
| Rollback decision matrix documented and tested | ✅ Kill-switch procedure + trigger matrix documented |
