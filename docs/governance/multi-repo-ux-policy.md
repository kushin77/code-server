# Enterprise Policies for Multi-Repo UX

**Purpose**: Enterprise Policies for Multi-Repo UX — reference and operational document.

**Status**: Active  
**Version**: 1.0.0  
**Date**: 2026-04-20  
**Closes**: #724  
**Schema**: [`config/policies/multi-repo-ux-policy.json`](../../config/policies/multi-repo-ux-policy.json)

---

## Purpose

Define enforceable, auditable enterprise policy controls for the multi-repo developer navigation experience. Policies govern resource limits, persistence behavior, telemetry, and feature rollout flags — with admin-enforced defaults and scoped user overrides where safe.

---

## Policy Tiers

| Tier | Who Sets It | Who Can Override | Override Scope |
|---|---|---|---|
| `admin-enforced` | Platform admin (via env/config) | Not overridable | — |
| `user-managed` | User preference | User (within admin bounds) | `profile` or `session` |

All policy values load from `config/policies/multi-repo-ux-policy.json` at startup and can be overridden via environment variables following the pattern `MULTI_REPO_POLICY_<KEY_UPPER>`.

---

## Policy Keys

| Key | Default | Tier | User Override | Description |
|---|---|---|---|---|
| `max_open_repos` | 10 | admin-enforced | No | Max simultaneously open repo workspaces |
| `persistence_enabled` | true | admin-enforced | Yes (session) | Enable per-repo context persistence |
| `persistence_depth_days` | 30 | admin-enforced | No | Days to retain session snapshots |
| `terminal_replay_enabled` | false | admin-enforced | Yes (per-repo) | Allow terminal history replay on restore |
| `telemetry_level` | standard | admin-enforced | No | Navigation telemetry depth |
| `home_view_enabled` | true | admin-enforced | Yes (session) | Enable home view with status cards |
| `toolbar_tabs_enabled` | true | admin-enforced | No | Enable toolbar workspace tabs |
| `favorites_max` | 10 | user-managed | Yes (profile) | Max pinned repos per user |
| `recents_max` | 20 | admin-enforced | Yes (profile) | Recent repos shown |
| `snapshot_retention_limit_mb` | 100 | admin-enforced | No | Max snapshot storage per user (MB) |

---

## Feature Flags

Feature flags under `feature_flags.*` control staged rollout per capability (see #725). Each flag maps directly to a phase in the phased delivery plan (ADR-004).

```json
{
  "feature_flags": {
    "toolbar_tabs": true,
    "home_view": true,
    "persistence": true,
    "command_switcher": true
  }
}
```

Flags are evaluated at session start. Changes take effect on the next login unless a live-reload endpoint is configured.

---

## Conformance Enforcement

### Runtime checks

- Policy is validated against the JSON schema on load; startup fails if schema is invalid.
- Per-session conformance is checked every `check_interval_seconds` (default: 300).
- Violations are written to `artifacts/policy-reports/multi-repo-ux-conformance.jsonl`.

### Audit events emitted

| Event | When |
|---|---|
| `policy.loaded` | On startup; records effective policy hash |
| `policy.override_attempted` | When user attempts an override |
| `policy.violation_detected` | When runtime state violates policy |
| `policy.snapshot_limit_exceeded` | When user snapshot storage exceeds limit |

### CI conformance gate

The `opa-policy-conformance.yml` workflow includes policy schema validation. A new conformance check can be added for multi-repo-ux-policy:

```bash
opa eval --data config/policies/multi-repo-ux-policy.json \
         --input artifacts/policy-reports/multi-repo-ux-conformance.jsonl \
         'data.multi_repo.conformance.violations' \
  | jq 'if . == [] then "PASS" else error("Policy violations detected") end'
```

---

## Policy Changes

All policy key changes must:
1. Increment `version` in the schema file.
2. Be reviewed and approved by the Platform Engineering owner.
3. Emit a `policy.loaded` event with the new effective hash after deployment.
4. Be reversible within one deploy cycle (rollback = revert schema + redeploy).

---

## Acceptance Criteria Status

| AC | Status |
|---|---|
| Policy schema documented and versioned | ✅ `config/policies/multi-repo-ux-policy.json` v1.0.0 |
| Policy can enforce/limit multi-repo features by tier | ✅ admin-enforced + user-managed tiers defined |
| Non-compliant client behavior is detected and reported | ✅ conformance checks + audit event log |
| Policy changes are auditable and reversible | ✅ version field + rollback procedure defined |