# Windows DC to Portal Capability Matrix

Parent issue: #743  
Parent epic: #742

## Objective
Define how classic Windows-domain-control-plane capabilities map to open-source portal components in the target architecture.

## Capability Mapping

| Legacy Capability (Windows/DC era) | Target Control-Plane Component | Authoritative Owner | Notes |
|---|---|---|---|
| Identity provider and group claims | Keycloak/Auth service + identity sync layer | Security Engineering | Source of truth for user and group claims used by portal RBAC. |
| Access policy authoring and evaluation | OPA policy service + signed policy bundles | Platform Governance | Central decision point for CI/runtime policy checks. |
| Repository governance baseline | GitHub org ruleset baseline + reconcile workflow | Platform Governance | Enforced via ruleset drift scan and reconcile automation. |
| IDE extension allowlist and marketplace block | Policy manifest + extension supply chain validator | Developer Platform | Curated extension channel only; signature and hash checks required. |
| Session provisioning and role profile application | code-server entrypoint + role profile seeders | Developer Platform | Applies immutable T1 and recommended T2 baseline at startup. |
| Revocation and break-glass workflows | Appsmith operator console + revocation broker | Security Operations | Explicit emergency path with audit-only elevation windows. |
| Audit event storage and traceability | JSONL audit emitters + Prometheus/Loki/Grafana pipelines | SRE/Observability | Unified event schema required for cross-system correlation. |
| Secrets lifecycle and signing material | Vault-backed key management | Security Engineering | Signing keys and policy secrets rotate under Vault policy. |
| Compliance drift detection | Daily governance and conformance CI workflows | Platform Governance | Drift creates actionable remediation artifacts. |

## Ownership Model

| Domain | Primary Owner | Secondary Owner | Approval Requirement |
|---|---|---|---|
| Identity and claims | Security Engineering | Platform Governance | Security lead approval |
| Policy and governance standards | Platform Governance | Security Engineering | Platform + Security joint approval |
| IDE runtime enforcement | Developer Platform | SRE | Developer Platform approval |
| Audit and retention | SRE/Observability | Security Operations | SRE approval |
| Break-glass and incident overrides | Security Operations | Platform Governance | Security Operations approval |

## Integration Boundaries

- Keycloak/Auth produces identities and claims; it does not evaluate policy decisions.
- OPA evaluates policy and emits decisions; it does not own user identity lifecycle.
- Appsmith provides operator UX only; policy truth remains in versioned repository artifacts.
- Backstage provides developer-facing control-plane discovery and dashboards; it is not the policy engine.
- CI workflows enforce merge gates; runtime services enforce session/operation gates.

## Non-Goals and Anti-Patterns

- No per-repo policy forks for baseline controls.
- No unsigned waiver or policy-bundle acceptance.
- No direct manual edits to production policy state outside pull-request flow.
- No long-lived break-glass roles without expiration and audit trail.
- No hidden control logic in ad-hoc scripts that bypass canonical policy services.

## Approval Checklist

- [ ] Platform Governance review complete
- [ ] Security Engineering review complete
- [ ] SRE/Observability review complete
- [ ] Architecture sign-off captured in issue #743

## Change Control

All updates to this matrix require:
1. Pull request with rationale and blast-radius section.
2. Update to docs/POLICY-CHANGELOG.md if normative policy ownership shifts.
3. Reviewer approval from at least one owner in impacted domain.
