# Security Hardening Guide

**Purpose**: Security Hardening Guide — reference and operational document.

This guide consolidates mandatory security controls for infrastructure, services, and operational workflows.

## 1. Secret Management

- Default secret source is Google Secret Manager (GSM).
- Vault may be used where runtime secret brokering is required.
- Do not commit credentials, tokens, or keys to repository files.
- Enforce fail-closed secret contracts for deploy-time variables.
- Rotate production secrets at least quarterly or immediately after exposure.

### Secret Rotation Minimums

- OAuth client secrets: every 90 days
- Database credentials: every 90 days
- Service account keys (if used): every 90 days or eliminate in favor of workload identity
- Emergency rotation: within 24 hours of incident declaration

## 2. Access Control and RBAC

- Use least-privilege role assignments.
- Separate operational roles: deploy, observe, and security administration.
- Require auditable approvals for elevated or break-glass access.
- Remove stale accounts and stale privileges during monthly review.

## 3. Network and Ingress Hardening

- Restrict management interfaces to trusted networks or VPN path.
- Enforce TLS at ingress.
- Keep proxy/header behavior explicit and reviewed for redirect/auth regressions.
- Validate failover path security before production readiness approval.

## 4. Workload Identity

- Prefer workload identity and service accounts for machine-to-machine access.
- Avoid static credentials in environment defaults.
- Scope identity permissions to minimum required resources.

## 5. Audit Logging and Evidence

- Log authentication outcomes, authorization denials, and privileged operations.
- Preserve deployment and incident evidence in linked GitHub issue/PR artifacts.
- Ensure log retention aligns with compliance and incident forensics needs.

## 6. Break-Glass Access

- Define emergency access owners and approval chain.
- Time-box emergency credentials and revoke immediately after use.
- Record reason, duration, actions, and validation evidence.

## 7. PR Security Review Checklist

- [ ] No secrets committed or exposed in defaults
- [ ] Secret source and rotation impact documented
- [ ] RBAC/access impact reviewed
- [ ] Network/ingress behavior validated
- [ ] Audit logging impact addressed
- [ ] Rollback path defined and tested

## 8. Cross-References

- Threat model: [security/THREAT-MODEL-2026-04-19.md](security/THREAT-MODEL-2026-04-19.md)
- Operations index: [ops/OPERATIONS-INDEX.md](ops/OPERATIONS-INDEX.md)
- Secret rotation schedule: [ops/SECRETS-ROTATION-SCHEDULE.md](ops/SECRETS-ROTATION-SCHEDULE.md)
- DR plan: [ops/DISASTER-RECOVERY-PLAN.md](ops/DISASTER-RECOVERY-PLAN.md)
- Incident playbook: [ops/INCIDENT-RESPONSE-PLAYBOOK.md](ops/INCIDENT-RESPONSE-PLAYBOOK.md)
- Ops compliance checklist: [ops/OPS-COMPLIANCE-CHECKLIST.md](ops/OPS-COMPLIANCE-CHECKLIST.md)
- Governance policy index: [governance/POLICY-INDEX.md](governance/POLICY-INDEX.md)

<!-- Runbook tracking: #1674 -->
