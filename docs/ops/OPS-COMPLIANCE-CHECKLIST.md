# Operations Compliance Checklist

Use this checklist before merge for P0/P1 changes and before production redeploy.

## Governance

- [ ] Issue is open and linked in PR with `Fixes #N`
- [ ] PR uses conventional commit and readiness gate sections
- [ ] Updated runbooks are linked in PR
- [ ] Waiver issue linked or marked `none`

## Security

- [ ] No hardcoded credentials or tokens in changed files
- [ ] Secret source is GSM or Vault (no weak fallback defaults)
- [ ] Access changes include least-privilege rationale
- [ ] Audit logging impact reviewed

## Reliability

- [ ] Rollback command is documented and tested
- [ ] Service health checks pass after change
- [ ] SLO impact assessed and acceptable
- [ ] Failover/failback implications reviewed

## Validation

- [ ] Core endpoints validated (portal, IDE, static assets)
- [ ] Logs reviewed for auth/ingress regressions
- [ ] CI checks for touched areas are green or waived with justification
- [ ] Evidence attached to issue or PR comments

## Deployment Safety

- [ ] Change can be applied incrementally or with targeted recreate
- [ ] Blast radius identified and communicated
- [ ] Operator on-call notified for non-trivial rollout
- [ ] Post-deploy verification commands prepared

## Sign-off

- Reviewer:
- Date:
- Related issue(s):
- Related PR:
