# GitHub Free Maximization Report

- Generated: 2026-04-20T15:44:38+00:00
- Workflows scanned: 96
- Scheduled workflows: 30
- GitHub-hosted runner mentions: 180
- Self-hosted runner mentions: 10
- External actions pinned: 330
- External actions unpinned: 0
- Cache uses: 2
- Artifact uses: 36
- Max artifact retention days: 90
- GH API usage hits in workflows: 62

## Run History Baseline

- Total runs in `artifacts/metrics/gh-runs-raw.json`: 200
- Success: 83
- Failure: 56
- Skipped: 60
- Skip ratio: 30.00%

## Policy Notes
- Pinned external actions are the baseline; keep them immutable so supply-chain drift stays low.
- Artifact retention should remain capped at 90 days.
- Cache-backed installs and generated reports are preferred to repeated raw re-downloads.
- Scheduled workflows should exist only where they produce a measurable operational signal.
- Skip-heavy gating workflows indicate avoided waste when they intentionally short-circuit no-op paths.

## Optimization Plan
- Keep GitHub-hosted runners only where native GitHub integration is required.
- Keep artifact retention at or below 90 days.
- Re-use pinned first-party actions and shared scripts instead of duplicating workflow logic.
- Prefer cache-backed dependency installs over cold fetches on every run.
- Review run-history trend monthly so skip ratio and workflow count stay visible.

## Workflow Inventory

| Workflow | uses | pinned external | unpinned external | cache uses | artifact uses | runners | retention-days | scheduled |
|---|---:|---:|---:|---:|---:|---|---|---|
| TEMPLATE-ci-build.yml | 7 | 7 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| TEMPLATE-ci-lint.yml | 4 | 4 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| TEMPLATE-ci-security.yml | 12 | 12 | 0 | 0 | 0 | ubuntu-latest: 6 | n/a | yes |
| TEMPLATE-ci-tests.yml | 6 | 6 | 0 | 0 | 0 | ubuntu-latest: 3 | n/a | no |
| TEMPLATE-security-scans.yml | 4 | 4 | 0 | 0 | 0 | ubuntu-latest: 3 | n/a | no |
| TEMPLATE-validate-caddyfile.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| TEMPLATE-validate-compose.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| TEMPLATE-validate-iac.yml | 5 | 5 | 0 | 0 | 0 | ubuntu-latest: 3 | n/a | no |
| ai-indexing-quality-gate.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| assign-pr-reviewers.yml | 6 | 6 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| autonomous-issue-triage.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| autopilot-setup-state-reconciler.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| bootstrap-ci-test.yml | 3 | 3 | 0 | 0 | 0 | ubuntu-latest: 3 | n/a | no |
| branch-cleanup.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| ci-validate.yml | 38 | 38 | 0 | 1 | 1 | ubuntu-latest: 32 | 90 | no |
| cleanup-stale-branches.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| cloudflare-admin-access-verify.yml | 3 | 3 | 0 | 0 | 1 | ubuntu-latest: 1 | 30 | yes |
| cloudflare-log-triage.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| code-smell-governance.yml | 3 | 3 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | no |
| config-drift-detector.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| core-conformance-suite.yml | 3 | 3 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | no |
| cost-monitoring.yml | 5 | 5 | 0 | 0 | 1 | ubuntu-latest: 2 | 90 | yes |
| deduplication-guard.yml | 4 | 4 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| dependency-health-audit.yml | 18 | 18 | 0 | 0 | 4 | ubuntu-latest: 5 | 90, 90, 90, 90 | yes |
| deploy.yml | 14 | 13 | 0 | 0 | 1 | ubuntu-latest: 5, self-hosted: 1 | n/a | no |
| deprecated-doc-stubs-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| deprecated-docs-pointer-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| deprecated-script-shims-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| deprecated-workflows-removed-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| dns-service-discovery-enforcement.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | 30 | no |
| do-not-use-config-surfaces-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| docker-storage-hygiene.yml | 11 | 11 | 0 | 0 | 2 | ubuntu-latest: 5 | 90, 90 | yes |
| docs-governance.yml | 3 | 3 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | yes |
| docs-standards-enforcement.yml | 13 | 13 | 0 | 0 | 3 | ubuntu-latest: 6 | 90, 90, 90 | yes |
| dual-track-ci.yml | 10 | 10 | 0 | 0 | 2 | self-hosted: 2, ubuntu-latest: 1 | 7, 7 | yes |
| e2e-authenticated-failover-continuity.yml | 3 | 3 | 0 | 0 | 1 | self-hosted: 1 | 7 | no |
| e2e-playwright-kit.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| e2e-profile-coverage.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| e2e-smoke-suite.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| enforce-branch-naming.yml | 0 | 0 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| enforce-priority-labels.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| enforce-repo-structure.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| error-triage-weekly-report.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | yes |
| error-triage.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| github-free-maximization.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | 90 | yes |
| global-dedup-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| golden-rule-enforce-redeploy.yml | 6 | 6 | 0 | 0 | 0 | self-hosted  # Must run on production host: 1, ubuntu-latest: 1 | n/a | no |
| governance-enforcement.yml | 3 | 3 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| governance-monthly-report.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| governance-waiver-audit.yml | 4 | 4 | 0 | 0 | 1 | ubuntu-latest: 2 | n/a | yes |
| governance-weekly-report.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | yes |
| gpu-upgrade-note-dedup-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| ide-blackbox-monitor.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| issue-duplicate-sentry.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| kubernetes-log-triage.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| linux-native-enforcement.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| ollama-contract-coverage.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| ollama-gpu-routing-failover.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| ollama-model-promotion-gates.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| org-governance-drift-scan.yml | 3 | 3 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | yes |
| org-governance-reconcile.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| org-repo-onboarding-dispatch.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| phase-1-certification-gate.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| phase-1-design-gate.yml | 4 | 4 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| phase-13-deploy.yml | 4 | 4 | 0 | 0 | 1 | ubuntu-latest: 2 | 30 | yes |
| phase-2-code-review-gate.yml | 5 | 5 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| phase-3-performance-gate.yml | 4 | 4 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| phase-7d-cloudflare-validation.yml | 7 | 7 | 0 | 0 | 0 | ubuntu-latest: 3, self-hosted: 2 | n/a | no |
| phase-7d-haproxy-validation.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| phase-7d-health-validation.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| pnpm-lockfile-governance.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| policy-bundle-governance.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | no |
| policy-check.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| policy-ssot-guard.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | no |
| portal-oauth-redeploy.yml | 3 | 3 | 0 | 0 | 0 | [self-hosted, onprem, portal-oauth-redeploy]: 1 | n/a | no |
| post-deploy-certification.yml | 5 | 5 | 0 | 0 | 0 | ubuntu-latest: 3 | n/a | no |
| post-merge-cleanup-deploy.yml | 9 | 9 | 0 | 0 | 0 | ubuntu-latest: 5 | n/a | no |
| production-readiness-gate.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| qa-coverage-gates.yml | 5 | 5 | 0 | 1 | 1 | ubuntu-latest: 1 | 30 | yes |
| repo-aware-ai-pipeline.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| secrets-rotation-audit.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | yes |
| secretsless-ai-access.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| security.yml | 6 | 4 | 0 | 0 | 1 | ubuntu-latest: 3 | n/a | yes |
| session-status-mirror-dedup-guard.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| shared-library-catalog-guard.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | no |
| shell-library-bats.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | no |
| ssot-integrity-auditor.yml | 3 | 3 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | yes |
| storage-hygiene-audit.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 1 | n/a | yes |
| terraform-drift-detection.yml | 5 | 5 | 0 | 0 | 1 | ubuntu-latest: 1 | 30 | yes |
| validate-config.yml | 7 | 4 | 0 | 0 | 0 | ubuntu-latest: 4 | n/a | no |
| validate-env.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 2 | n/a | no |
| validate-issue-governance.yml | 1 | 1 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| validate-quality-gates.yml | 2 | 2 | 0 | 0 | 1 | ubuntu-latest: 2 | n/a | no |
| validate.yml | 2 | 2 | 0 | 0 | 0 | ubuntu-latest: 1 | n/a | no |
| vpn-e2e-gate.yml | 1 | 1 | 0 | 0 | 0 | self-hosted: 1 | n/a | no |
| vpn-service-account-endpoint-validation.yml | 1 | 1 | 0 | 0 | 0 | self-hosted: 1 | n/a | no |

## Validation Status

- Strict mode: PASS
- Violations: 0 unpinned actions, 0 retention overruns

## Actionable Next Step

- Keep the current workflow inventory under review and maintain the 90-day artifact ceiling while reusing pinned actions and cache-backed installs.
