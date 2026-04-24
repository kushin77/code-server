# Operations Index

This document is the operations SSOT entry point for production runtime and incident handling.

## Scope

- Primary production host: `192.168.168.31` (`ssh akushnir@192.168.168.31`)
- Replica host: `192.168.168.42`
- Deployment mode: on-premises Docker Compose with optional `monitoring`, `tracing`, and `ai` profiles

## Canonical Operational Docs

- Deployment checklist: [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)
- NAS architecture: [../NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md)
- NAS contract: host `192.168.168.56`, export `/export`, mount `/mnt/nas`, protocol `nfs4`
- Port ownership map: [PORT-OWNERSHIP-MAP.md](PORT-OWNERSHIP-MAP.md)
- Disaster recovery plan: [DISASTER-RECOVERY-PLAN.md](DISASTER-RECOVERY-PLAN.md)
- Edge access baseline: [EDGE-ACCESS-BASELINE.md](EDGE-ACCESS-BASELINE.md)
- Incident response playbook: [INCIDENT-RESPONSE-PLAYBOOK.md](INCIDENT-RESPONSE-PLAYBOOK.md)
- Operations compliance checklist: [OPS-COMPLIANCE-CHECKLIST.md](OPS-COMPLIANCE-CHECKLIST.md)
- Secret rotation schedule: [SECRETS-ROTATION-SCHEDULE.md](SECRETS-ROTATION-SCHEDULE.md)
- External browser QA smoke tests: [EXTERNAL-BROWSER-QA-SMOKE-TESTS.md](EXTERNAL-BROWSER-QA-SMOKE-TESTS.md)
- Ephemeral workspace lifecycle: [../ephemeral-workspace-lifecycle-755.md](../ephemeral-workspace-lifecycle-755.md)
- Session FinOps guardrails: [SESSION-FINOPS-GUARDRAILS.md](SESSION-FINOPS-GUARDRAILS.md)
- Performance tuning: [../PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- Shared libraries guide: [../SHARED-LIBRARIES.md](../SHARED-LIBRARIES.md)
- Security hardening guide: [../SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
- Platform SLOs: [../slos/PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md)

## Core Runbooks

- Recovery runbook: [../runbooks/backup-recovery.md](../runbooks/backup-recovery.md)
- Production readiness gate: [../runbooks/production-readiness-gate.md](../runbooks/production-readiness-gate.md)
- Ops folder index: [README.md](README.md)
- Full redeploy certification: [../runbooks/full-redeploy-certification.md](../runbooks/full-redeploy-certification.md)
- SSOT drift dashboard: [../status/SSOT-DRIFT-DASHBOARD.md](../status/SSOT-DRIFT-DASHBOARD.md)

## Operational Rules

1. Run deploy operations on the production host, not local Windows.
2. Treat GitHub issues as work SSOT for prioritization and completion tracking.
3. Prefer fail-closed secret handling (GSM or Vault) and reject weak defaults.
4. Require rollback command and verification evidence for all non-trivial changes.

## Change Control

For all P0/P1 changes:

1. Link PR to issue with `Fixes #N`.
2. Attach validation evidence (health, logs, endpoint checks).
3. Update impacted runbooks in this index.
4. Confirm compliance checklist before merge.

## Last Updated

- Date: 2026-04-19
- Owner: Platform Engineering
