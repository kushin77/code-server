---
title: "Open in App bootstrap orchestrator: policy-gated local acceleration with deterministic rollback"
labels: [enhancement, P1-high, component/dev-tools, component/platform, component/security, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Implement a deterministic Open in App flow that can provision and update local acceleration safely after successful RBAC-authenticated browser login.

## Why This Is Critical
The brainstorm requires: access granted in backend, successful browser login, Open in App click, then auto deploy. This is the right UX, but must be implemented with strong safety and rollback guarantees.

## Scope
- Browser-to-companion handshake design.
- One-time bootstrap token issuance and validation.
- Deployment profile selection (thin, power, elite) with policy constraints.
- Rollback strategy on failed update or drift.

## Out Of Scope
- Full local environment replacement.
- Hidden persistent installers with unrestricted host access.

## Acceptance Criteria
- [ ] Open in App button visible only for authorized roles and compliant devices.
- [ ] Bootstrap token is one-time, short TTL, audience-bound, and signed.
- [ ] Companion endpoint validates token, nonce, origin, and device posture before action.
- [ ] Bootstrap flow supports idempotent retries with consistent end-state.
- [ ] Update flow supports canary rollout and immediate rollback.
- [ ] Clear user-facing states: provisioning, healthy, degraded, blocked-policy, revoked.
- [ ] Session logout or revocation tears down privileged local capabilities within SLO.
- [ ] End-to-end tests cover first install, update, downgrade block, revoke, and recovery.

## Operational Requirements
- Versioned manifests for image, extension pack, and policy bundle.
- Signed artifact verification before execution.
- Centralized telemetry of bootstrap outcome by tenant and version.

## Dependencies
- Parent: #650
- Related: #657, #655, #653

## Closure
End-to-end flow works from browser RBAC login to managed local acceleration with audited actions and rollback coverage.
