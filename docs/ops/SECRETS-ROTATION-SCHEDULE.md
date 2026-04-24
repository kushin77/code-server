# Secrets Rotation Schedule

This document defines the quarterly rotation policy, automation entrypoints, and evidence requirements for production secrets.

## Rotation Frequency

- Minimum cadence: every 90 days
- Emergency cadence: within 24 hours after suspected exposure

## Scope

- Google OAuth client secret
- oauth2-proxy cookie secret
- code-server password
- PostgreSQL password
- Redis password
- Cloudflare API token
- GitHub token used by automation

## Rotation Calendar

- Q1 window: Jan 1 to Jan 31
- Q2 window: Apr 1 to Apr 30
- Q3 window: Jul 1 to Jul 31
- Q4 window: Oct 1 to Oct 31

## Automation

Use the rotation helper script:

```bash
bash scripts/security/rotate-secrets-quarterly.sh --dry-run
bash scripts/security/rotate-secrets-quarterly.sh --execute
```

The script checks GSM/Vault references, creates a rotation report, and enforces non-empty replacement values for required keys in execution mode.

## Alerting

- CI alert when rotation report is older than 90 days
- Immediate alert when a tracked env file contains non-placeholder secret literals

## Evidence Requirements

For each rotation cycle, attach:

- Rotation timestamp (UTC)
- Rotated secret IDs
- Validation checks run
- Service health checks after rotation
- Linked issue/PR evidence

## Ownership

- Primary owner: Platform Engineering
- Secondary owner: Security Engineering

## Related Docs

- [SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
- [OPERATIONS-INDEX.md](OPERATIONS-INDEX.md)
- [OPS-COMPLIANCE-CHECKLIST.md](OPS-COMPLIANCE-CHECKLIST.md)
