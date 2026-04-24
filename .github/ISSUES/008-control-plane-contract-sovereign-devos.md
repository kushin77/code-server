---
title: "Sovereign DevOS Contract: portal control plane and workstation data plane boundary"
labels: [enhancement, P1-high, component/architecture, component/security, component/platform, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Define and enforce a hard contract where the portal is the control plane and the IDE workstation is the execution/data plane.

## Why This Is Critical
The brainstorm correctly aims for a thin-client OS model, but currently mixes identity, orchestration, deployment bootstrap, and runtime policy decisions across layers. Without a strict contract, implementation will drift into brittle, duplicated logic and security regressions.

## Scope
- Define authoritative ownership for identity, policy, session lifecycle, deployment intent, and audit.
- Define workstation responsibilities for rendering, local acceleration, ephemeral cache, and policy enforcement hooks.
- Define control-plane APIs and signed policy bundle format.

## Out Of Scope
- Building custom kernel, kiosk lockdown, or endpoint management bypassing enterprise IT controls.
- Any design that requires permanent local admin/root access by default.

## Acceptance Criteria
- [ ] Contract document exists: docs/architecture/control-plane-contract.md.
- [ ] API spec exists: docs/api/portal-workstation-control-plane.yaml.
- [ ] Signed policy bundle schema exists with versioning and backward compatibility rules.
- [ ] Explicit ownership matrix exists for authn, authz, secrets, config, runtime enforcement, and revocation.
- [ ] Sequence diagrams exist for login, open-in-app bootstrap, policy refresh, revoke, and outage mode.
- [ ] Fail-safe rules are documented: deny-by-default for privileged operations when contract validation fails.
- [ ] Contract validation tests added in CI (schema and compatibility tests).

## Required Design Decisions
- Session authority source and token minting chain.
- Propagation SLO for revocation events.
- Allowed local cache lifetime and encrypted storage requirements.
- Offline behavior policy for read-only versus write operations.

## Risks To Address
- Token replay between browser and local companion.
- Policy drift between portal and workstation.
- Hidden coupling to one IdP or one network provider.

## Success Metrics
- 100 percent of workstation sessions map to a portal-issued session id.
- Revocation propagated within target SLO in p95.
- Zero policy evaluation from unsigned local policy sources.

## Dependencies
- Parent: #650
- Related: #657, #655, #653, #622

## Closure
Contract approved, APIs versioned, tests green, and referenced by all downstream implementation issues.
