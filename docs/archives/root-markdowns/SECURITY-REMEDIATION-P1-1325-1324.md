# P1 Security Remediation: Private Keys in Git (#1325, #1324)

## Status: IN PROGRESS

### Issues
- **#1325**: private-key in .env.oidc:7
- **#1324**: private-key in .env.phase-2-additions:24

### Root Cause
RSA private keys and other sensitive credentials were committed to git repository, exposing them in:
1. Commit history
2. Any clone of the repository
3. Any fork or mirror
4. GitHub API if repository is public

### Severity
🔴 **CRITICAL** - Immediate action required

### Remediation Steps

#### Phase 1: Immediate Containment (NOW)
- [x] Identify all vulnerable files
- [x] Create template files without secrets
- [x] Update .gitignore
- [ ] Create PR to remove vulnerable files
- [ ] Merge PR to main
- [ ] Run `git filter-branch` to remove from history

#### Phase 2: Secret Migration (URGENT)
- [ ] Rotate all keys in production
- [ ] Upload new keys to Google Secret Manager
- [ ] Update CI/CD pipelines to load from GSM
- [ ] Update deployment scripts to use GSM bootstrap
- [ ] Verify production uses GSM-sourced secrets

#### Phase 3: Verification
- [ ] Run trivy scan - should show 0 P1 findings
- [ ] Audit git history - no private keys visible
- [ ] Test deployment with GSM-only secrets
- [ ] Monitor logs for secret injection issues

### Files Involved
- `.env.oidc` → `.env.oidc.template` + GSM `oidc-issuer-signing-key`
- `.env.phase-2-additions` → `.env.phase-2-additions.template` + GSM secrets

### Git Filter-Branch Command (Phase 1)
```bash
# WARNING: This rewrites git history. Coordinate with team first.
git filter-branch --tree-filter 'rm -f .env.oidc .env.phase-2-additions' -- --all
git push origin --force-with-lease
```

### GSM Bootstrap (Phase 2)
Update startup script to load secrets:
```bash
export OIDC_ISSUER_SIGNING_KEY=$(gcloud secrets versions access latest --secret=oidc-issuer-signing-key)
export OIDC_CLIENT_SECRET=$(gcloud secrets versions access latest --secret=oidc-client-secret)
# ... repeat for all secrets
```

### Key Rotation Checklist
- [ ] Generate new RSA key pair
- [ ] Update signing/verification keys in GSM
- [ ] Update OIDC issuer endpoint
- [ ] Invalidate old JWT tokens (set expiry to now)
- [ ] Restart authentication services
- [ ] Monitor for auth failures

### Timeline
- **NOW**: Contain issue, create templates
- **Today**: Create PR, merge, rotate keys
- **Tomorrow**: Verify GSM bootstrap working, full audit

### References
- GitHub Issue: https://github.com/kushin77/code-server/issues/1325
- GitHub Issue: https://github.com/kushin77/code-server/issues/1324
- Copilot Instructions: Rule 3 (Configuration Separation)
- Google Secret Manager: https://cloud.google.com/secret-manager

