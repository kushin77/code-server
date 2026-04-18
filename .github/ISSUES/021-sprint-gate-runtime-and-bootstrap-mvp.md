---
title: "Sprint Gate: Runtime and Open in App bootstrap MVP"
labels: [sprint, P1-high, component/dev-tools, component/platform, status/ready, effort/l]
assignees: []
---

## Sprint Objective
Deliver end-to-end Open in App bootstrap MVP with signed manifests and rollback capability.

## In Scope
- Browser authorization gating for Open in App.
- Bootstrap token flow and companion validation.
- Profile resolution and runtime provisioning.

## Sprint Backlog
- [ ] Implement one-time token flow with nonce and origin checks.
- [ ] Implement companion endpoint policy and posture validation.
- [ ] Implement signed manifest verification for install and update.
- [ ] Implement rollback on failed update.
- [ ] Add E2E tests for success, block, revoke, and rollback paths.

## Exit Criteria
- [ ] MVP flow works in controlled environment with full audit trace.
- [ ] Rollback path tested and deterministic.
- [ ] Critical defects triaged with owner and resolution path.

## Dependencies
- Parent: #014
- Depends on: #020
- Drives: #016
