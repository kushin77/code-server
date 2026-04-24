---
title: "EPIC: Managed workstation runtime and Open in App lifecycle"
labels: [epic, P1-high, component/dev-tools, component/platform, component/reliability, status/ready, effort/l]
assignees: []
---

## Goal
Deliver deterministic Open in App activation and managed runtime lifecycle for thin, power, and elite profiles.

## Scope
- Companion bootstrap endpoint and handshake hardening.
- Profile-aware runtime provisioning and updates.
- Safe rollback and policy-driven disable path.

## Detailed Work Items
- [ ] Implement one-time bootstrap token flow with nonce and audience checks.
- [ ] Add runtime profile resolver based on policy and device capability.
- [ ] Implement signed manifest validation before install or update.
- [ ] Build canary-to-general rollout strategy for runtime updates.
- [ ] Build failure recovery path with deterministic rollback.

## Acceptance Criteria
- [ ] Authorized browser sessions can launch Open in App with consistent results.
- [ ] Unauthorized or non-compliant devices are blocked with clear reasons.
- [ ] Failed updates auto-rollback and surface actionable telemetry.
- [ ] Session revoke removes privileged runtime capabilities within SLO.

## Dependencies
- Parent: #014
- Blocks: #021
- Related: #010

## Definition Of Done
- [ ] E2E coverage for install, update, rollback, revoke, and re-provision.
- [ ] Operational dashboards show success, failure, and rollback rates.
- [ ] User states and support playbook documented.
