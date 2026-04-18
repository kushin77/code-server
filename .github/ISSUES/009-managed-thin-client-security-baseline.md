---
title: "Managed thin client security baseline: zero-trust, anti-tamper, and regulated controls"
labels: [enhancement, P1-high, component/security, component/compliance, component/platform, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Establish enterprise security baseline for local workstation companion and thin-client runtime, suitable for SOC2 and regulated environments.

## Why This Is Critical
The brainstorm includes aggressive controls (kiosk, no local access, auto deploy, kill switch). Without formal threat modeling and compliance controls, this can create legal, operational, and endpoint-risk failures.

## Scope
- Threat model for browser, local companion, tunnel, token flow, and policy channel.
- Baseline controls: device trust, least privilege runtime, signed binaries, mTLS, key rotation, audit integrity.
- Safe anti-tamper response levels and incident handling.

## Out Of Scope
- Malware-like persistence behavior.
- Disabling user/admin controls outside approved enterprise endpoint policy.

## Acceptance Criteria
- [ ] STRIDE threat model documented in docs/security/threat-model-thin-client.md.
- [ ] Security control matrix documented with control owner, evidence, and test mapping.
- [ ] Companion binary signing and verification implemented.
- [ ] Mutual TLS with certificate rotation implemented for companion to control plane.
- [ ] Hardware-bound device posture check integrated (TPM or platform equivalent where available).
- [ ] Token TTL, refresh policy, and replay protections defined and tested.
- [ ] Audit trail tamper resistance validated (hash chain or equivalent).
- [ ] Incident playbooks added for token compromise, endpoint theft, and tunnel compromise.

## Must-Have Constraints
- No hardcoded credentials or long-lived static tokens on endpoints.
- No root-required runtime for normal user operations.
- Companion must run with minimal privileges and explicit allowlist of actions.

## Security Tests
- [ ] Replay and token substitution tests.
- [ ] Local API abuse tests for companion localhost endpoints.
- [ ] Certificate pinning bypass attempt tests.
- [ ] Policy downgrade and stale-policy execution tests.

## Dependencies
- Parent: #650
- Related: #643, #657

## Closure
Threat model signed off, controls implemented, negative tests passing, and compliance evidence generated in CI.
