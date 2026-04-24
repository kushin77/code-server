---
title: "Sprint Gate: Foundation contract and threat model"
labels: [sprint, P1-high, component/architecture, component/security, status/ready, effort/m]
assignees: []
---

## Sprint Objective
Lock the system contract and threat baseline so downstream work cannot diverge.

## In Scope
- Contract draft, schema draft, and compatibility policy.
- Threat model and initial control matrix.
- Initial conformance test harness.

## Sprint Backlog
- [ ] Deliver first contract spec with state machine and ownership matrix.
- [ ] Deliver first SLO definitions for revocation and policy propagation.
- [ ] Deliver threat model and top risk controls.
- [ ] Add CI checks for schema validation and contract linting.

## Exit Criteria
- [ ] Contract and threat model approved by architecture and security owners.
- [ ] CI checks passing for contract artifacts.
- [ ] Blocker list created for unresolved design decisions.

## Dependencies
- Parent: #014
- Drives: #015, #017
