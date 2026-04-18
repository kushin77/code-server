## Summary
Production apex OAuth is now blocked in the GCP/GSM bootstrap phase, not in the compose helper or SSH transport.

Observed on 2026-04-18:
- Latest main run `24610858158` reaches `google-github-actions/auth@v2` with the canonical numeric provider path and fails with `invalid_target`.
- Local gcloud refresh from this workstation returns `invalid_rapt`, so provider discovery cannot be completed here.
- Canonical GCP/GSM bootstrap guidance lives in [../ops/PORTAL-OAUTH-GCP-GSM-BOOTSTRAP-695.md](../ops/PORTAL-OAUTH-GCP-GSM-BOOTSTRAP-695.md).

## Root Cause
Execution path is codified; the active blocker is secret/provider resolution:
- The portal workflow now targets self-hosted execution with branch-scoped concurrency.
- The GSM bootstrap path depends on canonical Workload Identity provider resolution.
- The backing workload identity pool/provider does not currently resolve in GCP from the current session.
- The repository-side secret surface is limited to `GCP_PROJECT`, `GCP_SA`, and `GCP_WIF_PROVIDER`.
- There is no repo-side fallback that can recreate the missing GCP provider resource.

## Required Work (Immutable + Idempotent)
- [ ] Recreate or correct the GCP workload identity pool/provider so the canonical numeric provider path resolves.
- [ ] Confirm the exact secret contract for `GCP_PROJECT` versus `GCP_WIF_PROVIDER`.
- [ ] Re-run the portal workflow and capture the first successful GSM bootstrap.
- [ ] Verify redirects:
  - apex -> https://kushnir.cloud/oauth2/callback
  - ide -> https://ide.kushnir.cloud/oauth2/callback
- [ ] Capture evidence in issue comment (exact curl -I location lines).

## Acceptance Criteria
- [ ] Live apex callback uses kushnir.cloud callback.
- [ ] Live ide callback uses ide.kushnir.cloud callback.
- [ ] The bootstrap path is codified and repeatable from a registered reachable runner.
- [ ] No manual in-container edits; compose-driven idempotent deploy only.

## References
- Branch: feat/671-issue-671
- [Portal OAuth GCP/GSM bootstrap runbook](../ops/PORTAL-OAUTH-GCP-GSM-BOOTSTRAP-695.md)
- Portal 502 follow-up issue: `#709`
- Failing script in current runtime: `bash scripts/deploy/redeploy-portal-oauth-routing.sh`
- Deploy workflow run with queued GitHub-hosted job: `24608080969`
- Secret-provisioning issue: `#690` (resolved)
- Network-reachability follow-up issue: `#692`
- Self-hosted validation runs: `portal-oauth-redeploy.yml #24608948773`, `vpn-e2e-gate.yml #24608949154`
- Latest published portal run: `#24609258258` failed at SSH auth with `Permission denied (publickey,password)`
- Branch fix run: `#24609414318` failed because the self-hosted runner lacked `docker`
