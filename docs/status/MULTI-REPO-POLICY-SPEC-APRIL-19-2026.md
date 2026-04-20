# Multi-Repo Policy Spec - April 19, 2026

Status: Active
Scope: Enterprise policy controls for multi-repo behavior, including defaults, limits, compliance, and auditability.

## Purpose

This is the canonical policy artifact for issue #724. It defines the policy keys and enforcement model needed to keep multi-repo behavior consistent, compliant, and reversible across users, teams, and org-wide deployments.

## Policy Goals

- Keep the default multi-repo experience safe and predictable.
- Allow organizations to constrain behavior by tier and compliance needs.
- Make policy changes auditable, reversible, and testable in CI/runtime.
- Avoid hard-coding policy decisions inside UI components.

## Policy Domains

| Domain | Policy Keys | Effect |
| --- | --- | --- |
| Repo scope | `maxRepos`, `allowedRepoPatterns`, `teamWorkspaceAllowList` | Limits the number and shape of available repositories. |
| Persistence | `restoreDepth`, `retentionDays`, `allowTerminalRestore`, `allowTaskRestore` | Controls how much session state is persisted and restored. |
| Telemetry | `telemetryLevel`, `auditEventLevel`, `metricsSamplingRate` | Controls observability and reporting detail. |
| UX features | `enableWorkspaceTabs`, `enableHomeView`, `enableQuickSwitch`, `enableFavorites` | Enables or disables the main multi-repo surfaces. |
| Compliance | `requireApprovalForSharedSets`, `requireRBACForRestore`, `blockUnsafeTerminalReplay` | Enforces governance and safety requirements. |

## Policy Tiers

1. Personal tier: user-owned settings within safe limits.
2. Team tier: shared defaults with policy-approved overrides.
3. Org tier: admin-enforced hard limits and compliance requirements.

## Enforcement Model

- Policy is evaluated before a repo switch, context restore, or shared workspace launch.
- Hard-deny rules override user preferences.
- Non-compliant clients receive explicit error states and remediation hints.
- Audit events are emitted for policy changes, denied access, and privileged restore actions.

## Validation Model

- CI should validate schema shape and version compatibility.
- Runtime should reject unknown or malformed policy payloads.
- Policy changes should have an accompanying rollback path.
- Metrics should record compliance rate and policy-drift incidents.

## Closure Criteria

- The policy schema is versioned and documented.
- Multi-repo features can be constrained by tier and compliance rules.
- Non-compliant behavior is detected and reported.
- Policy changes are auditable and reversible.

## Cross-References

- Multi-repo interaction model: [../architecture/ADR-004-MULTI-REPO-INTERACTION-MODEL.md](../architecture/ADR-004-MULTI-REPO-INTERACTION-MODEL.md)
- Developer context hub: [../architecture/ADR-005-DEVELOPER-CONTEXT-HUB.md](../architecture/ADR-005-DEVELOPER-CONTEXT-HUB.md)
- Program tracker index: [PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](PROGRAM-TRACKER-INDEX-APRIL-19-2026.md)
