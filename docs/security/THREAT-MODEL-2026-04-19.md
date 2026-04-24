# Threat Model

**Purpose**: Threat Model runbook — operational procedure for THREAT MODEL 2026 04 19 response.

This document captures the current red-team view of the repository on 2026-04-19. It is intentionally scoped to the live platform surfaces that matter for auth, ingress, secrets, CI/CD, and admin operations.

## Objective

Treat the platform as adversarially targeted and reduce exploitable paths before they reach production impact.

## In Scope

- Auth flow and OAuth/OIDC boundaries
- Ingress, reverse proxy, and header-handling behavior
- Secret lifecycle, secret sources, and deploy-time secret contracts
- CI/CD integrity, artifact immutability, and release gating
- Admin access, SSH transport, and failover operations
- Runtime data stores and operational telemetry

## Trust Boundaries

1. Public internet to edge ingress
2. Edge ingress to auth and portal services
3. Auth services to protected upstream applications
4. CI/CD automation to deploy-time secrets and infrastructure state
5. Operators to production hosts through SSH/VPN/admin tooling
6. Runtime services to databases, Redis, Vault, and Google Secret Manager

## Current Attack Paths

### 1. Auth redirect and header manipulation

An attacker can try to exploit proxy header handling or redirect normalization to force misrouting, open redirects, or login loop behavior.

Impact:

- Authentication bypass attempts
- Denial of service through redirect loops
- Confusion around origin and host-bound trust

Existing controls:

- Explicit proxy and ingress configuration
- Production validation of portal static delivery and auth redirects
- Failover-aware deployment checks

Residual risk:

- Header behavior must stay explicit across every ingress variant and proxy layer.

### 2. Secret exposure through defaults or drift

An attacker can target weak defaults, template fallbacks, or config drift to recover credentials or force weak deploy-time values.

Impact:

- Credential compromise
- Unauthorized access to databases or admin surfaces
- Silent weakening of deploy-time security posture

Existing controls:

- Fail-closed secret contracts
- GSM-first secret sourcing
- Vault-backed runtime brokering where required
- Quarterly rotation policy

Residual risk:

- Any new env var, compose override, or IaC path can reintroduce fallback behavior if it is not checked at deploy time.

### 3. CI/CD supply-chain compromise

An attacker can try to tamper with build inputs, mutable image tags, or backend/state handling to inject untrusted artifacts.

Impact:

- Malicious code in deployed images
- State corruption or unauthorized infrastructure changes
- Undetected drift between source and runtime

Existing controls:

- Image immutability checks
- Terraform backend hardening checks
- Security-scanning workflows

Residual risk:

- Any unpinned image reference or unverified workflow path weakens the integrity chain.

### 4. Lateral movement from admin access

An attacker with SSH, VPN, or operator access can pivot into privileged deploy paths, data stores, or failover controls.

Impact:

- Production compromise
- Service interruption
- Secret exfiltration

Existing controls:

- Least-privilege operational roles
- VPN-restricted management paths
- Edge/access baseline that gates SSH through Cloudflare Tunnel and the dedicated SSH proxy
- Failover status checks before action

Residual risk:

- Operator access remains a high-value target and must be narrowly scoped and auditable.
- Direct SSH exposure must remain out of the default edge posture and should be treated as a regression.

### 5. Database and service credential abuse

An attacker who reaches a service container or deployment context can attempt credential reuse against PostgreSQL, Redis, or other internal dependencies.

Impact:

- Data exfiltration or tampering
- Service disruption
- Expanded internal reach

Existing controls:

- Secret rotation policy
- Non-public service exposure
- Explicit environment contracts

Residual risk:

- Shared or long-lived credentials increase blast radius if they leak.

## Prioritized Exploit Chains

1. Public ingress misconfiguration leads to auth loop or origin confusion, then attacker abuses login flow instability to bypass or DoS the portal.
2. Weak secret fallback enters compose or IaC, then leaked credentials allow access to internal services.
3. Mutable build artifact or unpinned deployment input is introduced, then attacker gains code execution in a runtime image.
4. Operator access is compromised, then attacker pivots to secrets, databases, and failover controls.

## Security Control Gap Matrix

| Area | Risk | Current Control | Gap | Severity | Closure Evidence |
| --- | --- | --- | --- | --- | --- |
| Auth / ingress | Redirect loops, host-header abuse, origin confusion | Explicit proxy config and runtime validation | Keep every ingress/proxy variant aligned with the same header policy | High | Portal and auth smoke checks with 200/302 behavior recorded in issue evidence |
| Secrets | Weak defaults or undeclared fallbacks | GSM-first, fail-closed secret contracts | All secret-bearing env vars must be enforced consistently across compose, IaC, and scripts | Critical | Secrets scan, deploy-time contract checks, and rotation evidence |
| CI/CD | Supply-chain or artifact drift | Immutability and backend hardening checks | Pin every deployable artifact and verify workflow inputs | High | CI gates for image immutability and Terraform backend hardening |
| Admin access | Lateral movement from SSH/VPN/operator paths | Least privilege and scoped admin access | Strengthen break-glass policy and audit chain for every privileged action | High | Access review log, operator approvals, and incident trail |
| Runtime dependencies | Credential reuse into internal stores | Network segmentation and rotation policy | Reduce credential lifetime and scope per service | Medium | Rotation schedule and service-specific credential inventory |
| Observability | Blind spots in adversarial paths | Logs and deployment evidence in issues | Add explicit regression checks for auth, ingress, and failover surfaces | Medium | CI smoke checks and linked issue evidence |

## Hardening Backlog

| Severity | Item | Owner | Closure Evidence |
| --- | --- | --- | --- |
| Critical | Remove all secret fallbacks from active deploy paths | Platform / IaC | No fallback env values, deploy-time validation passes, secret scan passes |
| High | Keep proxy/header policy consistent across every ingress surface | Platform / ingress | Auth redirect smoke tests pass for portal and IDE paths |
| High | Pin and verify all build and deploy artifacts | CI / release | Immutability and backend hardening checks pass in CI |
| High | Make operator access auditable and time-bounded | Operations | Break-glass procedure documented and exercised |
| Medium | Shorten credential lifetime where feasible | Platform / security | Rotation schedule and enforcement evidence recorded |
| Medium | Expand regression checks for auth and failover | QA / ops | Automated smoke and failover status checks run in CI or release gates |

## Regression Checks

These checks should stay in the pipeline or release gate set:

- Secrets scan for committed credentials and weak defaults
- Image immutability check for every release artifact
- Terraform backend hardening check before infra changes
- Secret rotation SLA check for all production secret classes
- OIDC and vault validation for token and identity flows
- Auth redirect and static asset smoke checks
- Failover status check before any production hardening claim

## Acceptance Criteria

- High-risk exploit paths are remediated or accepted with an expiry date.
- IAM and secret boundaries are minimal, explicit, and auditable.
- Security checks prevent reintroduction of known vulnerabilities.

## Accepted Risks

| Risk | Owner | Expiry | Status | Notes |
| --- | --- | --- | --- | --- |
| Operator access remains a high-value target and must be narrowly scoped and auditable. | Operations | 2026-05-03 | Accepted | Break-glass access is documented, time-boxed, and reviewed in the incident playbook. |
| Shared or long-lived credentials increase blast radius if they leak. | Security Engineering | 2026-05-03 | Accepted | Rotation policy, GSM-first sourcing, and fail-closed deploy contracts are in place while remaining hardening work continues. |
| Any unpinned image reference or unverified workflow path weakens the integrity chain. | Platform Engineering | 2026-05-03 | Accepted | Image immutability and Terraform backend checks are enforced in CI for the active release path. |

## Cross-References

- Security hardening guide: [../SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
- Operations index: [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- Secret rotation schedule: [../ops/SECRETS-ROTATION-SCHEDULE.md](../ops/SECRETS-ROTATION-SCHEDULE.md)
- Incident playbook: [../ops/INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md)
- Issue tracker SSOT: [../status/ISSUE-TRACKER-APRIL-19-2026.md](../status/ISSUE-TRACKER-APRIL-19-2026.md)