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
- GitHub Actions deploy secret is provisioned, and the standalone portal workflow now targets self-hosted execution; a temporary runner in this session validated the workflow path, but the live production apply still needs a production-capable host
- Local dry-run validation passes with `bash scripts/deploy/redeploy-portal-oauth-routing.sh --dry-run --local`

## Required Work (Immutable + Idempotent)
- [ ] Provide a reachable execution path for the redeploy workflow (self-hosted runner or approved tunnel/proxy)
- [ ] Keep the deploy path secret-driven, immutable, and idempotent
- [ ] Execute `scripts/deploy/redeploy-portal-oauth-routing.sh` through the `portal-oauth-redeploy.yml` workflow against production
- [ ] Verify redirects:
  - apex -> https://kushnir.cloud/oauth2/callback
  - ide -> https://ide.kushnir.cloud/oauth2/callback
- [ ] Capture evidence in issue comment (exact curl -I location lines)

## Acceptance Criteria
- [ ] Live apex callback uses kushnir.cloud callback
- [ ] Live ide callback uses ide.kushnir.cloud callback
- [ ] Redeploy execution path is codified and repeatable from a registered reachable runner
- [ ] No manual in-container edits; compose-driven idempotent deploy only

## References
- Branch: feat/671-issue-671
- Failing script in current runtime: bash scripts/deploy/redeploy-portal-oauth-routing.sh
- Deploy workflow run with queued GitHub-hosted job: 24608080969
- Secret-provisioning issue: #690 (resolved)
- Network-reachability follow-up issue: #692
- Self-hosted validation runs: portal-oauth-redeploy.yml #24608948773, vpn-e2e-gate.yml #24608949154
