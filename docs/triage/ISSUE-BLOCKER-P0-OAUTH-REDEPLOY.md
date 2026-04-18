## Summary
Production apex OAuth is still misrouted: kushnir.cloud starts OAuth with IDE callback instead of portal callback.

Observed on 2026-04-18:
- https://kushnir.cloud/oauth2/start?rd=/ returns redirect_uri=https://ide.kushnir.cloud/oauth2/callback
- expected redirect_uri=https://kushnir.cloud/oauth2/callback

## Root Cause
Execution path is blocked, not implementation:
- IaC compose split callback fix exists in branch (OAUTH2_PROXY_IDE_REDIRECT_URL + OAUTH2_PROXY_PORTAL_REDIRECT_URL)
- idempotent redeploy script exists: scripts/deploy/redeploy-portal-oauth-routing.sh
- direct non-interactive SSH to 192.168.168.31 unavailable from current runtime
- self-hosted Actions runner count is currently 0 for this repo

## Required Work (Immutable + Idempotent)
- [ ] Register at least one self-hosted GitHub Actions runner for kushin77/code-server with self-hosted,linux labels
- [ ] Ensure runner has docker + compose permissions on prod host path /home/akushnir/code-server-enterprise
- [ ] Execute scripts/deploy/redeploy-portal-oauth-routing.sh (or equivalent workflow job) against production
- [ ] Verify redirects:
  - apex -> https://kushnir.cloud/oauth2/callback
  - ide -> https://ide.kushnir.cloud/oauth2/callback
- [ ] Capture evidence in issue comment (exact curl -I location lines)

## Acceptance Criteria
- [ ] Live apex callback uses kushnir.cloud callback
- [ ] Live ide callback uses ide.kushnir.cloud callback
- [ ] Redeploy execution path is codified and repeatable (runner or SSH automation)
- [ ] No manual in-container edits; compose-driven idempotent deploy only

## References
- Branch: feat/671-issue-671
- Failing script in current runtime: bash scripts/deploy/redeploy-portal-oauth-routing.sh
- Deploy workflow run with queued self-hosted job: 24597100366
