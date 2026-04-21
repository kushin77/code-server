# Compliance Checklist

Purpose: canonical audit and evidence checklist for production changes, reviews, and operational readiness.

## Scope

- Applies to P0/P1 changes, release sign-off, and production redeploys
- Complements the operational checklist in [ops/OPS-COMPLIANCE-CHECKLIST.md](ops/OPS-COMPLIANCE-CHECKLIST.md)

## Required Evidence

- Linked GitHub issue with acceptance criteria
- Validation output for the changed surface
- Rollback command or last known-good reference
- Security review notes for secret or access changes
- Post-deploy confirmation for production-impacting changes

## Audit Sections

### Governance

- [ ] Issue is linked in the PR or change record
- [ ] Canonical docs were updated instead of duplicating guidance
- [ ] Waiver or exception status is documented if applicable

### Security

- [ ] No secrets or credentials are introduced in tracked files
- [ ] Secret source is GSM or Vault where applicable
- [ ] Access control changes are least-privilege and audited

### Reliability

- [ ] Rollback path is documented and verified
- [ ] Health checks or smoke tests passed after the change
- [ ] Any failover or recovery impact is documented

### Operations

- [ ] Deployment checklist completed
- [ ] Validation evidence attached to the issue
- [ ] Monitoring or alerting implications reviewed

## Related Docs

- [ops/OPERATIONS-INDEX.md](ops/OPERATIONS-INDEX.md)
- [ops/DEPLOYMENT-CHECKLIST.md](ops/DEPLOYMENT-CHECKLIST.md)
- [ops/OPS-COMPLIANCE-CHECKLIST.md](ops/OPS-COMPLIANCE-CHECKLIST.md)
- [ops/DISASTER-RECOVERY-PLAN.md](ops/DISASTER-RECOVERY-PLAN.md)
- [ops/INCIDENT-RESPONSE-PLAYBOOK.md](ops/INCIDENT-RESPONSE-PLAYBOOK.md)

<!-- Runbook tracking: #1674 -->
