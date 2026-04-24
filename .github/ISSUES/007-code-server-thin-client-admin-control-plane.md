---
title: "Treat code-server as a thin client with admin-portal-managed identity, session, and policy control"
labels: [enhancement, P1-high, component/dev-tools, component/security, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Make code-server behave as an execution surface and thin client, not the primary authority for user access, session lifecycle, or workspace policy.

## Description
Today the repo already has identity, RBAC, and policy-baseline work across `#388`, `#385`, and the active epic `#650`, but it does not yet state the platform contract explicitly enough: user control and access decisions should be managed globally by the admin portal and enforced by code-server as a downstream consumer.

This issue captures that architectural requirement so implementation work does not drift back toward local IDE state, repo-specific auth behavior, or per-instance access rules.

## Why This Matters
- Human identity, entitlement, and revocation should have one global source of truth.
- Code-server should not own long-lived access state beyond short-lived cached assertions needed to function.
- Session suspension, forced logout, repository entitlement changes, and workspace policy updates should be initiated centrally from the admin portal.
- Treating code-server as a thin client reduces drift, simplifies compliance, and keeps desktop/thin-client behavior consistent across repos and devices.

## Acceptance Criteria
- [ ] Admin portal is the system of record for user identity, roles, repository/workspace entitlements, and session state.
- [ ] Code-server consumes signed identity and policy assertions from the admin portal or its delegated identity provider instead of relying on repo-local or instance-local access rules.
- [ ] Admin portal can force session revoke, suspend user access, and invalidate active IDE sessions globally.
- [ ] Repository access, workspace policy, and extension/tool allowlists are centrally defined and enforced consistently for every repo opened in code-server.
- [ ] Code-server startup and session restore paths converge on the same portal-issued policy contract with deterministic failure behavior.
- [ ] Audit logs correlate portal actions, code-server enforcement decisions, and affected user sessions with a shared correlation ID.
- [ ] Loss of portal reachability has a documented fail-safe mode: deny-by-default for privileged changes, with tightly scoped read-only or cached behavior only where explicitly approved.
- [ ] Drift detection exists for locally mutated IDE settings, policy exceptions, and stale sessions.

## Dependencies
- Parent: #650
- Architectural context: #385
- Identity contract foundation: #388
- Related: #653
- Related: #655
- Related: #622

## Implementation Notes
- Define an explicit admin-portal-to-code-server control-plane contract for:
  - session issuance and revocation
  - user suspension and recovery
  - repository and workspace entitlement lookup
  - policy bundles for extensions, terminals, environment variables, secrets, and AI features
  - audit/event propagation
- Keep code-server enforcement stateless where possible; any cache should be short-lived, observable, and revocable.
- Prefer one global policy bundle over repo-specific policy forks unless there is a signed exception path.
- Reuse the org-wide auth and policy baseline from `#650` rather than creating a parallel auth model.

## Success Metrics
- 100% of active IDE sessions are traceable to a portal-issued identity and policy bundle.
- Session revoke from admin portal is reflected in code-server within the target propagation window.
- New repos opened in code-server require no repo-local auth customization to inherit the correct policy.
- Drift alerts exist for local policy mutation and stale entitlement caches.

## References
- `#650` EPIC: Org-Wide Auth & Policy Baseline for code-server
- `#385` Dual-Portal Architecture
- `#388` Identity, RBAC, and workload auth standardization