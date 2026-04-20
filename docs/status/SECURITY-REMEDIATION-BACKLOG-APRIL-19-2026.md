# Security Remediation Backlog - April 19, 2026

Status: Active
Scope: Prioritized exploit-path remediations and time-bounded accepted risks for the current security red-team campaign.

## Purpose

This is the canonical remediation backlog for issue #831. The threat model already exists; this file turns it into an executable queue with owners, priority, target evidence, and explicit expiry for any accepted risk.

## Evidence Reviewed

- [../security/THREAT-MODEL-2026-04-19.md](../security/THREAT-MODEL-2026-04-19.md)
- [../SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
- [../ops/SECRETS-ROTATION-SCHEDULE.md](../ops/SECRETS-ROTATION-SCHEDULE.md)
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [../ops/OPS-COMPLIANCE-CHECKLIST.md](../ops/OPS-COMPLIANCE-CHECKLIST.md)
- [../governance/CONFIG-SSOT.md](../governance/CONFIG-SSOT.md)
- [../ops/DEPLOYMENT-CHECKLIST.md](../ops/DEPLOYMENT-CHECKLIST.md)

## Prioritized Remediation Queue

| Priority | Item | Risk Being Reduced | Owner | Target Evidence |
| --- | --- | --- | --- | --- |
| P0 | Remove all secret fallbacks from active deploy paths | Weak or undeclared fallbacks can reintroduce credential compromise and hidden drift. | Platform / IaC | Deploy-time validation passes; no fallback secret values remain in compose, IaC, or scripts. |
| P0 | Keep ingress and auth header policy explicit across every surface | Header drift can cause redirect loops, misrouting, or auth confusion. | Platform / Ingress | Auth redirect smoke tests pass for portal and IDE with current live endpoints. |
| P0 | Enforce pinning and immutability for deployable artifacts | Mutable artifacts weaken supply-chain integrity and reproducibility. | CI / Release | Image-immutability and backend-hardening checks pass with no mutable references. |
| P1 | Formalize break-glass and operator-access review | Privileged access is a high-value lateral-movement path. | Operations / Security | Break-glass procedure documented, exercised, and tied to audit evidence. |
| P1 | Shorten secret lifetime where feasible | Long-lived credentials increase the blast radius of leakage. | Platform / Security | Rotation schedule executed, evidence recorded, and emergency rotation path tested. |
| P1 | Expand regression checks for auth and failover surfaces | Missing checks let regressions survive into production. | QA / Ops | Auth, static, and failover smoke checks run in the gate with captured evidence. |
| P2 | Centralize service telemetry ownership | Unclear alert ownership slows detection and response. | Operations | Observability-gap list closed or time-bounded with owners and alerts. |
| P2 | Require explicit expiry for all accepted risks | Open-ended exceptions become permanent policy drift. | Security / Governance | Any accepted risk has an owner, expiry date, and review cadence. |

## Current Accepted Risks

| Risk | Why It Is Temporarily Accepted | Expiry | Owner | Closure Condition |
| --- | --- | --- | --- | --- |
| None recorded | The current repo evidence supports a remediation-first approach. | N/A | N/A | Any future exception must be added here with expiry and approval. |

## Remediation Order

1. Close secret-fallback and immutability gaps first.
2. Keep ingress/auth behavior aligned with the current production contract.
3. Exercise operator access, rotation, and failover paths with real evidence.
4. Convert remaining observability and telemetry items into tracked follow-ups with owners.
5. Record any exception as accepted risk with a hard expiry date instead of a permanent waiver.

## Validation Checklist

- [ ] Secret fallbacks removed from active paths.
- [ ] Auth and ingress smoke checks pass on the live stack.
- [ ] Artifact immutability checks pass in CI.
- [ ] Rotation evidence exists for the current secret classes.
- [ ] Break-glass procedure is documented and exercised.
- [ ] Every accepted risk has an owner and expiry.
- [ ] Any new exploit path is either remediated or explicitly time-bounded.

## Closure Criteria

- High-risk exploit paths are either remediated or moved into a time-bounded accepted-risk entry.
- IAM and secret boundaries remain minimal and auditable.
- CI regression checks prevent known security issues from reappearing.
- The issue trail contains the evidence needed for review and sign-off.

## Cross-References

- Threat model: [../security/THREAT-MODEL-2026-04-19.md](../security/THREAT-MODEL-2026-04-19.md)
- Hardening guide: [../SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
