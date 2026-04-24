---
title: "EPIC: Control plane contract and policy authority"
labels: [epic, P1-high, component/architecture, component/security, component/platform, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Establish the portal as authoritative control plane and enforce a signed, versioned contract consumed by workstation runtimes.

## Scope
- Contract model for identity, session, policy, revocation, and device posture.
- Signed policy bundle schema and compatibility policy.
- Explicit fail-safe behavior for outage and stale-policy scenarios.

## Detailed Work Items
- [ ] Author control-plane contract spec and lifecycle states.
- [ ] Define token minting and validation chain for browser and companion.
- [ ] Implement policy bundle signature verification and version negotiation.
- [ ] Add contract conformance tests in CI.
- [ ] Add correlation-id propagation across auth and policy paths.

## Acceptance Criteria
- [ ] Contract spec published and versioned.
- [ ] Policy bundles are signed and rejected when invalid, stale, or downgraded.
- [ ] Revocation propagation SLO measured and enforced.
- [ ] All policy evaluations traceable to portal authority.

## Dependencies
- Parent: #014
- Related: #008

## Definition Of Done
- [ ] CI conformance checks green.
- [ ] Integration tests for login, refresh, revoke, and outage mode green.
- [ ] Runbook for contract version rollouts published.
