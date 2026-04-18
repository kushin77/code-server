## Summary
Production apex OAuth is still misrouted: kushnir.cloud starts OAuth with IDE callback instead of portal callback.

Observed on 2026-04-18:
- https://kushnir.cloud/oauth2/start?rd=/ returns redirect_uri=https://ide.kushnir.cloud/oauth2/callback
- expected redirect_uri=https://kushnir.cloud/oauth2/callback

## Root Cause
Execution path is blocked, not implementation:
- IaC compose split callback fix exists in branch (OAUTH2_PROXY_IDE_REDIRECT_URL + OAUTH2_PROXY_PORTAL_REDIRECT_URL)
- idempotent redeploy script exists: scripts/deploy/redeploy-portal-oauth-routing.sh
- direct non-interactive SSH to 192.168.168.31 unavailable from current runtime shell
- GitHub-hosted deploy path now requires the production SSH key secret in Actions

## Required Work (Immutable + Idempotent)
- [ ] Add the production SSH private key as `DEPLOY_SSH_PRIVATE_KEY` in GitHub Actions secrets
- [ ] Keep the deploy path ephemeral by using the GitHub-hosted `ubuntu-latest` runner
- [ ] Execute `scripts/deploy/redeploy-portal-oauth-routing.sh` through the `portal-oauth-redeploy.yml` workflow against production
- [ ] Verify redirects:
  - apex -> https://kushnir.cloud/oauth2/callback
  - ide -> https://ide.kushnir.cloud/oauth2/callback
- [ ] Capture evidence in issue comment (exact curl -I location lines)

## Acceptance Criteria
- [ ] Live apex callback uses kushnir.cloud callback
- [ ] Live ide callback uses ide.kushnir.cloud callback
- [ ] Redeploy execution path is codified and repeatable (GitHub-hosted SSH automation)
- [ ] No manual in-container edits; compose-driven idempotent deploy only

## References
- Branch: feat/671-issue-671
- Failing script in current runtime: bash scripts/deploy/redeploy-portal-oauth-routing.sh
- Deploy workflow run with queued self-hosted job: 24597100366
- Follow-up secret-provisioning issue: #690
