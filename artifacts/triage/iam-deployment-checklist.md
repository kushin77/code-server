# IAM Phase 2/3/4 Deployment Checklist Dry Run

**Generated**: 2026-04-23T02:47:58+00:00
**Status**: READY TO EXECUTE

## Evidence Anchors

- Runbook: docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md
- Deployment readiness: artifacts/triage/deployment-readiness-report-20260423.md
- Staging validation: artifacts/staging/staging-validation-dry-run.md
- Phase 2 config: config/iam/PHASE-2.1-OIDC-ISSUER-CONFIGURATION.md
- Phase 3 SQL: config/iam/audit-logging-phase3-sql.sql
- Phase 4 SQL: config/iam/audit-logging-phase4.sql

## Checklist Summary

### Security Verification
- [x] Secrets rotation path documented
- [x] No hardcoded credentials required for the dry-run evidence set
- [x] HTTPS/OAuth configuration present in the repo
- [x] MFA/documentation references available

### Infrastructure Verification
- [x] Primary and replica deployment evidence available
- [x] Database replication evidence available
- [x] Redis Sentinel references available
- [x] NAS/staging storage references available

### Code Verification
- [x] Test suite evidence available
- [x] Deployment readiness report available
- [x] IAM phase configuration files available

### Documentation Verification
- [x] Runbook available
- [x] Incident/rollback references available
- [x] Team execution evidence available

## Deployment Day Readiness

The following should be executed during the actual deployment window:

- Backup current state
- Enable verbose logging
- Deploy oauth2-oidc-issuer service
- Verify OIDC discovery/JWKS/token endpoints
- Deploy JWT validation middleware
- Create RBAC tables and seed roles
- Deploy audit logging schema and service
- Run verification and produce final report

## Recommendation

Proceed with the scheduled IAM deployment window only after the full checklist is walked in order.

## Repository State

- Branch: feat/collab-2.1-voice-channel-1233
- Commit: 6ed4c739359df640595ed38b7b449089eb2e6ae7

