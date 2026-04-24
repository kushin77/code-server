---
title: "EPIC: Security and compliance baseline for regulated operation"
labels: [epic, P1-high, component/security, component/compliance, component/platform, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Provide enforceable security controls and auditable evidence sufficient for enterprise and regulated adoption.

## Scope
- Threat modeling and control matrix.
- Device trust, key handling, token policies, and mTLS.
- Audit evidence generation and incident runbooks.

## Detailed Work Items
- [ ] Complete threat model for browser, portal, companion, and tunnel paths.
- [ ] Define security control matrix with implementation owner and evidence mapping.
- [ ] Implement certificate and key rotation policies.
- [ ] Implement anti-replay, anti-downgrade, and anti-tamper checks.
- [ ] Add compliance evidence export pipeline for controls and tests.

## Acceptance Criteria
- [ ] All critical threats have implemented controls and negative tests.
- [ ] Key and token lifecycle controls validated by automated tests.
- [ ] Audit logs are immutable, correlated, and queryable.
- [ ] Incident response playbooks cover endpoint theft, token leak, and compromised tunnel.

## Dependencies
- Parent: #014
- Related: #009, #013

## Definition Of Done
- [ ] Security test suite green in CI.
- [ ] Control evidence package generated automatically.
- [ ] Security and compliance review sign-off captured.
