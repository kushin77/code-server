# Issue Tracker SSOT — April 19, 2026

This file is the canonical index for the current audit and remediation workstreams.

## Summary

Latest live issue audit shows the closed items below are already resolved in GitHub. The remaining work is tracked in the open epics and should be updated there rather than duplicated in new audit docs.

## P0 Blocking Work

No open P0 blockers remain in this tracker snapshot.

## Active Open Epics

- [#700](https://github.com/kushin77/code-server/issues/700) - Enterprise Global Governance Control Plane (Single Policy Authority)
- [#701](https://github.com/kushin77/code-server/issues/701) - Org-Wide GitHub Governance Enforcement
- [#705](https://github.com/kushin77/code-server/issues/705) - Centralized Waiver Governance
- [#706](https://github.com/kushin77/code-server/issues/706) - Governance Admin Center
- [#708](https://github.com/kushin77/code-server/issues/708) - OPA Policy Service Evolution
- [#717](https://github.com/kushin77/code-server/issues/717) - Session sync and continuity workstream
- [#718](https://github.com/kushin77/code-server/issues/718) - Repo indexing and navigation workstream
- [#719](https://github.com/kushin77/code-server/issues/719) - Safe restore and recovery workstream
- [#720](https://github.com/kushin77/code-server/issues/720) - Toolbar and UI navigation workstream
- [#721](https://github.com/kushin77/code-server/issues/721) - Isolation and tenancy guardrails
- [#722](https://github.com/kushin77/code-server/issues/722) - SLO guardrails and enforcement
- [#724](https://github.com/kushin77/code-server/issues/724) - Policy limit and control updates
- [#725](https://github.com/kushin77/code-server/issues/725) - Rollout flag and release coordination
- [#726](https://github.com/kushin77/code-server/issues/726) - ADR selection and decision tracking
- [#727](https://github.com/kushin77/code-server/issues/727) - Context hub integration
- [#742](https://github.com/kushin77/code-server/issues/742) - Open-source Control Plane Adoption

## Closed / Evidence Added

- [#764](https://github.com/kushin77/code-server/issues/764): backend hardening evidence comment added; CI hardening check passes and the issue is closed
- [#765](https://github.com/kushin77/code-server/issues/765): secret management evidence comment added; GSM bootstrap and rotation evidence are in place and the issue is closed
- [#770](https://github.com/kushin77/code-server/issues/770): documentation evidence comment added; canonical ops/security/docs surface created and the issue is closed
- [#776](https://github.com/kushin77/code-server/issues/776): monorepo governance evidence comment added; `docs/MONOREPO.md` created and the issue is closed
- [#777](https://github.com/kushin77/code-server/issues/777): CI/governance evidence comment added; validator scripts created and the issue is closed
- [#780](https://github.com/kushin77/code-server/issues/780): E2E evidence comment added; Playwright smoke suite ran and the issue is closed
- [#784](https://github.com/kushin77/code-server/issues/784): incident response evidence comment added; ops playbooks created and the issue is closed
- [#795](https://github.com/kushin77/code-server/issues/795): deployment checklist implemented in [docs/ops/DEPLOYMENT-CHECKLIST.md](../../docs/ops/DEPLOYMENT-CHECKLIST.md)
- [#796](https://github.com/kushin77/code-server/issues/796): branch policy implemented in [docs/ops/BRANCH-POLICY.md](../../docs/ops/BRANCH-POLICY.md) and cleanup workflows
- [#798](https://github.com/kushin77/code-server/issues/798): operations docs SSOT implemented in [docs/ops/OPERATIONS-INDEX.md](../../docs/ops/OPERATIONS-INDEX.md), [docs/slos/README.md](../../docs/slos/README.md), [docs/ops/DISASTER-RECOVERY-PLAN.md](../../docs/ops/DISASTER-RECOVERY-PLAN.md), and [docs/COMPLIANCE-CHECKLIST.md](../../docs/COMPLIANCE-CHECKLIST.md)
- [#799](https://github.com/kushin77/code-server/issues/799): security hardening evidence comment added; consolidated guide and rotation schedule created and the issue is closed
- [#801](https://github.com/kushin77/code-server/issues/801): Linux-native cleanup completed; active Windows/PowerShell references removed from scripts and docs, and [docs/SHARED-LIBRARIES.md](../../docs/SHARED-LIBRARIES.md) now indexes the canonical helper surface
- [#806](https://github.com/kushin77/code-server/issues/806): monorepo boundary enforcement now passes via [scripts/ci/validate-monorepo-target.sh](../../scripts/ci/validate-monorepo-target.sh) and the `pnpm test:boundaries` gate wired into CI
- [#833](https://github.com/kushin77/code-server/issues/833): elite enterprise hardening umbrella is closed after all child issues completed and the supporting SSOT artifacts were recorded
- [#845](https://github.com/kushin77/code-server/issues/845): NAS usage optimization SSOT added in [NAS-OPTIMIZATION-GOVERNANCE-APRIL-19-2026.md](NAS-OPTIMIZATION-GOVERNANCE-APRIL-19-2026.md) and the issue is closed in GitHub
- [#745](https://github.com/kushin77/code-server/issues/745), [#746](https://github.com/kushin77/code-server/issues/746), [#747](https://github.com/kushin77/code-server/issues/747), [#748](https://github.com/kushin77/code-server/issues/748): closed after validation with revocation, OIDC, OPA policy-service, and Vault signing-key contract artifacts in place

## Evidence Added

- [#762](https://github.com/kushin77/code-server/issues/762): live runtime verification comment added; portal CSS returns HTTP 200 with `text/css`, failover status shows primary/VIP alignment with both nodes healthy, and the GitHub issue is closed
- [#700](https://github.com/kushin77/code-server/issues/700): governance control-plane evidence comment added; canonical policy, waiver, and portal ADRs now provide the SSOT foundation
- [#701](https://github.com/kushin77/code-server/issues/701): org-wide governance enforcement evidence comment added; repo onboarding and structure checks now have live automation paths
- [#704](https://github.com/kushin77/code-server/issues/704): canonical policy SSOT and deduplication evidence added; policy index, domain registry, changelog, and CI guard now enforce policy uniqueness and precedence, and the issue is closed in GitHub
- [#706](https://github.com/kushin77/code-server/issues/706), [#742](https://github.com/kushin77/code-server/issues/742), [#745](https://github.com/kushin77/code-server/issues/745), [#746](https://github.com/kushin77/code-server/issues/746), [#747](https://github.com/kushin77/code-server/issues/747), [#748](https://github.com/kushin77/code-server/issues/748): control-plane evidence comments added for Backstage/Appsmith, revocation workflows, OIDC identity, OPA policy service, and Vault-backed signing keys
- [#748](https://github.com/kushin77/code-server/issues/748): vault signing-key contract validation added via [scripts/ci/validate-vault-signing-keys.sh](../../scripts/ci/validate-vault-signing-keys.sh) with artifact [artifacts/security/vault-signing-keys-report.json](../../artifacts/security/vault-signing-keys-report.json)
- [#746](https://github.com/kushin77/code-server/issues/746): OIDC issuer contract validation added via [scripts/ci/validate-oidc-issuer-contract.sh](../../scripts/ci/validate-oidc-issuer-contract.sh) with artifact [artifacts/security/oidc-issuer-contract-report.json](../../artifacts/security/oidc-issuer-contract-report.json)
- [#747](https://github.com/kushin77/code-server/issues/747): OPA policy service rollout validation added via [scripts/ci/validate-opa-policy-service.sh](../../scripts/ci/validate-opa-policy-service.sh) with artifact [artifacts/security/opa-policy-service-report.json](../../artifacts/security/opa-policy-service-report.json)
- [#745](https://github.com/kushin77/code-server/issues/745): strict revocation path validation added via [scripts/ci/validate-revocation-broker.sh](../../scripts/ci/validate-revocation-broker.sh) with artifact [artifacts/security/revocation-broker-report.json](../../artifacts/security/revocation-broker-report.json)
- [#717](https://github.com/kushin77/code-server/issues/717) through [#727](https://github.com/kushin77/code-server/issues/727): multi-repo navigation evidence comments added covering session sync, repo indexing, safe restore, toolbar tabs, isolation, SLO guardrails, policy limits, rollout flags, ADR selection, and context-hub integration

## Latest Runtime Validation

- Current live-stack baseline burst against `https://kushnir.cloud/static/css/main.c5955fd3.css` completed with 15/15 HTTP 200 responses at 5-way parallelism; average response time was 0.143s, min 0.075s, max 0.238s. Evidence was attached back to #805 and #828.
- Current live surface snapshot across `https://kushnir.cloud/static/css/main.c5955fd3.css`, `https://kushnir.cloud/`, and `https://ide.kushnir.cloud/` completed with 5/5 HTTP 200, 5/5 HTTP 403, and 5/5 HTTP 302 responses respectively; the portal static asset averaged 0.124s and the portal/IDE entry points remained stable under a small live burst. Evidence was attached back to #805 and #828.
- Canonical live-surface collector added at [../../scripts/ops/collect-live-surface-baseline.sh](../../scripts/ops/collect-live-surface-baseline.sh) with generated evidence in [../../artifacts/triage/live-surface-baseline.md](../../artifacts/triage/live-surface-baseline.md) and [../../artifacts/triage/live-surface-baseline.json](../../artifacts/triage/live-surface-baseline.json); the 2-request baseline capture returned portal 403, IDE 200, static asset 200, and OAuth start 200.
- Resilience campaign runner completed at [../../scripts/ops/run-resilience-campaign.sh](../../scripts/ops/run-resilience-campaign.sh) with generated evidence in [../../artifacts/triage/resilience-campaign.md](../../artifacts/triage/resilience-campaign.md) and [../../artifacts/triage/resilience-campaign.json](../../artifacts/triage/resilience-campaign.json); soak-lite completed, authenticated smoke passed after the Appsmith login contract was hardened, and failover continuity passed in unauthenticated mode.
- Current live sequential sample across `https://kushnir.cloud/static/css/main.c5955fd3.css`, `https://ide.kushnir.cloud/`, and `https://kushnir.cloud/oauth2/start?rd=%2F` completed with 30/30 HTTP 200, 30/30 HTTP 302, and 30/30 HTTP 302 responses respectively; the static asset averaged 0.060s, IDE root averaged 0.032s, and oauth2 start averaged 0.028s.
- Current failover checkpoint from `scripts/operations/redeploy/onprem/failover-orchestrate.sh --action status`: active host marker `192.168.168.31`, VIP owner `192.168.168.31`, primary health healthy, replica health healthy, and replica ingress healthy; the promote/failback drill completed successfully and returned the stack to the primary.
- `scripts/ci/validate-policy-domain-registry.sh`: passed with 0 errors and 0 warnings, regenerating `policy-domain-registry-report.json`
- `scripts/ci/validate-epic-ac-overlap.sh`: passed with 0 errors and 0 warnings, regenerating `epic-ac-overlap-report.json`
- `scripts/ci/check-terraform-backend-hardening.sh`: passed against `terraform/backend.tf`
- `scripts/governance/verify-policy-bundle.sh --manifest artifacts/policy-bundles/policy-bundle-1.0.0-canary.manifest.json`: passed bundle schema, digest, and catalog verification
- `scripts/security/rotate-secrets-quarterly.sh --dry-run`: now sources `scripts/fetch-gsm-secrets.sh` when available, exports the canonical `CLOUDFLARE_API_TOKEN` alias, and generates `artifacts/security/secrets-rotation-report.json` with any remaining missing references called out explicitly in dry-run mode
- `scripts/e2e-test-suite.sh --simulation --run all`: passed with 16 simulated checks passed and 2 skipped, confirming the wrapper and summary flow execute cleanly without QA storage state
- `bash -n` sweep across the 10 changed shell scripts completed cleanly; no parser failures were isolated after the earlier empty-path command issue
- `scripts/ci/check-error-handling-consistency.sh`: syntax-checked cleanly; advisory run now recognizes `scripts/ci/check-metadata-headers.sh`, `scripts/ci/check-no-hardcoded-credentials.sh`, `scripts/ci/validate-dedup-registry.sh`, `scripts/ci/check-no-windows-content.sh`, `scripts/ci/check-root-hygiene.sh`, and `scripts/ci/check-vpn-gate.sh` as sourced via canonical init, while the remaining warnings are pre-existing legacy scripts
- `scripts/ci/check-error-handling-consistency.sh`: syntax-checked cleanly; the checker now accepts nested script-local `../_common/init.sh` paths, `scripts/ci/PHASE-13-EMERGENCY-PROCEDURES.sh` and `scripts/ci/fix-github-auth.sh` were normalized to the canonical shared-init/strict-mode baseline, and the latest advisory run passes with no remaining warnings
- `.github/workflows/dual-track-ci.yml`: updated the enhancement/upstream matrices to Node 20.x and 22.x, isolated pnpm installs and upstream temp paths per run/job/matrix entry on the self-hosted runner, and editor diagnostics reported no YAML errors
- `src/services/opa-policy-service/index.ts`, `src/services/opa-policy-service/types.ts`, and `tests/unit/opa-policy-service/conformance.spec.ts`: `get_errors` returned no diagnostics

## Implemented / Evidence Added

- [#795](https://github.com/kushin77/code-server/issues/795): implemented in [docs/ops/DEPLOYMENT-CHECKLIST.md](../../docs/ops/DEPLOYMENT-CHECKLIST.md)
- [#796](https://github.com/kushin77/code-server/issues/796): implemented in [docs/ops/BRANCH-POLICY.md](../../docs/ops/BRANCH-POLICY.md) and cleanup workflows
- [#798](https://github.com/kushin77/code-server/issues/798): implemented in [docs/ops/OPERATIONS-INDEX.md](../../docs/ops/OPERATIONS-INDEX.md), [docs/slos/README.md](../../docs/slos/README.md), [docs/ops/DISASTER-RECOVERY-PLAN.md](../../docs/ops/DISASTER-RECOVERY-PLAN.md), and [docs/COMPLIANCE-CHECKLIST.md](../../docs/COMPLIANCE-CHECKLIST.md)
- [#704](https://github.com/kushin77/code-server/issues/704): evidence added in `policy-ssot-report.json` and `scripts/ci/check-policy-ssot.sh` (0 duplicates, 0 contradictions)
- [#705](https://github.com/kushin77/code-server/issues/705): evidence added in `artifacts/governance/waiver-inventory.json` and `artifacts/governance/waiver-inventory.md` from `config/governance-waivers.json`
- [#708](https://github.com/kushin77/code-server/issues/708): evidence added via `artifacts/policy-bundles/policy-bundle-1.0.0-canary.manifest.json` and `scripts/governance/verify-policy-bundle.sh`

## April 19 Triage Sweep

The current GitHub snapshot adds a new cluster of open tracking issues under #800 and the related P1/P2 workstreams (#802-#831), with #832 now complete and closed. Most are program trackers rather than implementation tasks. The repo already has concrete coverage for several of them, so the remaining work is to keep the umbrella issues current rather than duplicate status in new docs.

### Closed in GitHub, repo evidence retained

- #802 stale-reference cleanup has canonical guidance in [docs/ops/BRANCH-POLICY.md](../../docs/ops/BRANCH-POLICY.md), [docs/governance/elite-best-practices/clean-git-tree/CLEAN-TREE-PROCEDURE.md](../../docs/governance/elite-best-practices/clean-git-tree/CLEAN-TREE-PROCEDURE.md), and cleanup workflows, but the tracker issue remains open as the umbrella for stale-reference retirement.
- #807 branch hygiene: [docs/ops/BRANCH-POLICY.md](../../docs/ops/BRANCH-POLICY.md), [docs/governance/elite-best-practices/clean-git-tree/CLEAN-TREE-PROCEDURE.md](../../docs/governance/elite-best-practices/clean-git-tree/CLEAN-TREE-PROCEDURE.md), and cleanup workflows
- #808 shared-library documentation (closed in GitHub): [docs/SHARED-LIBRARIES.md](../../docs/SHARED-LIBRARIES.md)
- #810 container hardening (closed in GitHub): [scripts/ci/check-image-immutability.sh](../../scripts/ci/check-image-immutability.sh) and [docs/SECURITY-HARDENING-GUIDE.md](../../docs/SECURITY-HARDENING-GUIDE.md)
- #812 Terraform enforcement (closed in GitHub): [scripts/ci/check-terraform-backend-hardening.sh](../../scripts/ci/check-terraform-backend-hardening.sh) and [docs/COMPLIANCE-CHECKLIST.md](../../docs/COMPLIANCE-CHECKLIST.md)
- #818 secret lifecycle hardening (closed in GitHub): [scripts/security/rotate-secrets-quarterly.sh](../../scripts/security/rotate-secrets-quarterly.sh), [docs/SECURITY-HARDENING-GUIDE.md](../../docs/SECURITY-HARDENING-GUIDE.md), and [docs/ops/SECRETS-ROTATION-SCHEDULE.md](../../docs/ops/SECRETS-ROTATION-SCHEDULE.md)
- #820 Linux-native gate (closed in GitHub): [docs/SHARED-LIBRARIES.md](../../docs/SHARED-LIBRARIES.md) and [scripts/ci/check-error-handling-consistency.sh](../../scripts/ci/check-error-handling-consistency.sh)
- #821 authenticated E2E expansion (closed in GitHub): [scripts/e2e-test-suite.sh](../../scripts/e2e-test-suite.sh) and [tests/artifacts/playwright-results.json](../../tests/artifacts/playwright-results.json)
- #811 OAuth/endpoint contract (closed in GitHub): [scripts/ci/validate-oidc-issuer-contract.sh](../../scripts/ci/validate-oidc-issuer-contract.sh) and [artifacts/security/oidc-issuer-contract-report.json](../../artifacts/security/oidc-issuer-contract-report.json)

## Still open follow-up gaps

- #805 resilience campaign is now closed in GitHub; the current live evidence bundle is retained in [RESILIENCE-CAMPAIGN-APRIL-19-2026.md](RESILIENCE-CAMPAIGN-APRIL-19-2026.md).
- #828 performance engineering offensive is now closed in GitHub after current live latency, concurrency, memory, soak, and bottleneck evidence were captured.

### Repo-side SSOT coverage added

- #803 NAS topology SSOT now points at [docs/NAS-ARCHITECTURE.md](../../docs/NAS-ARCHITECTURE.md) and the canonical config map in [docs/governance/CONFIG-SSOT.md](../../docs/governance/CONFIG-SSOT.md). The issue is closed in GitHub.
- #809 endpoint/API index now includes the operational health surfaces in [docs/ops/ENDPOINT-CONTRACT-INDEX.md](../../docs/ops/ENDPOINT-CONTRACT-INDEX.md). The issue is closed in GitHub.
- #817 docs gap-analysis now has a sync check in [scripts/ci/sync-documentation-gaps.sh](../../scripts/ci/sync-documentation-gaps.sh) and CI coverage in [.github/workflows/ci-validate.yml](../../.github/workflows/ci-validate.yml). The issue is closed in GitHub.
- #819 continuous config SSOT drift prevention now generates a canonical report via [scripts/ci/generate-config-ssot-report.sh](../../scripts/ci/generate-config-ssot-report.sh) and runs through the drift pipeline. The issue is closed in GitHub.
- #823/#827 quality and CI audit now have a canonical report in [CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md](../../docs/status/CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md). These issues are closed in GitHub after the audit program completed.
- #824 readiness program now has a canonical scorecard in [READINESS-SCORECARD-APRIL-19-2026.md](../../docs/status/READINESS-SCORECARD-APRIL-19-2026.md). The issue is closed in GitHub after the hard-gate program completed.
- #825 assumption register now has a canonical register in [ASSUMPTION-REGISTER-APRIL-19-2026.md](../../docs/status/ASSUMPTION-REGISTER-APRIL-19-2026.md). The issue is closed in GitHub after the control-surface register was completed.
- #828 performance engineering offensive now has a canonical report in [PERFORMANCE-ENGINEERING-OFFENSIVE-APRIL-19-2026.md](../../docs/status/PERFORMANCE-ENGINEERING-OFFENSIVE-APRIL-19-2026.md) and the issue is closed in GitHub after the campaign completed.
- #830 production-hardening gate now has a canonical report in [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](../../docs/status/PRODUCTION-HARDENING-GATE-APRIL-19-2026.md) and is closed in GitHub after DR/on-call evidence, SLO policy, and explicit ownership were recorded.
- #831 security red-team campaign now has a canonical report in [../security/THREAT-MODEL-2026-04-19.md](../security/THREAT-MODEL-2026-04-19.md) and [../SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md), and is closed in GitHub after the remaining risks were time-bounded and accepted.
- #829 UX/UI excellence audit now has a canonical report in [UX-UI-EXCELLENCE-AUDIT-APRIL-19-2026.md](../../docs/status/UX-UI-EXCELLENCE-AUDIT-APRIL-19-2026.md). The issue is closed in GitHub after the login-recovery and browser smoke-test follow-through was validated.
- #805 resilience campaign now has a canonical report in [RESILIENCE-CAMPAIGN-APRIL-19-2026.md](../../docs/status/RESILIENCE-CAMPAIGN-APRIL-19-2026.md) and is closed in GitHub after baseline, soak-lite, authenticated smoke, and failover continuity evidence were captured.
- #828 performance engineering offensive now has a canonical report in [PERFORMANCE-ENGINEERING-OFFENSIVE-APRIL-19-2026.md](../../docs/status/PERFORMANCE-ENGINEERING-OFFENSIVE-APRIL-19-2026.md) and the issue is closed in GitHub after authenticated soak, higher-concurrency, and bottleneck evidence were captured.

### Program trackers that should stay summary-only

- #800 umbrella tracker remains the canonical pointer for the April 19 follow-up slice.
- #802 stale-reference cleanup remains open as the summary tracker for retired-path cleanup.
- #823 through #832 are executive/program trackers and should not be duplicated in implementation docs.

## Current Open Program Trackers

- #802 stale-reference cleanup remains open as the umbrella for archived/deprecated reference retirement.


## Recently Closed

- #823 ruthless code-quality teardown is backed by [docs/status/CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md](CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md) and now closed in GitHub.
- #824 FAANG brutal readiness program is backed by [docs/status/READINESS-SCORECARD-APRIL-19-2026.md](READINESS-SCORECARD-APRIL-19-2026.md) and now closed in GitHub.
- #825 assumption-assassin register is backed by [docs/status/ASSUMPTION-REGISTER-APRIL-19-2026.md](ASSUMPTION-REGISTER-APRIL-19-2026.md) and now closed in GitHub.
- #827 CI/CD ruthless audit is backed by [docs/status/CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md](CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md) and now closed in GitHub.
- #829 UX/UI product excellence audit is backed by [UX-UI-EXCELLENCE-AUDIT-APRIL-19-2026.md](UX-UI-EXCELLENCE-AUDIT-APRIL-19-2026.md) and now closed in GitHub.
- #828 performance engineering offensive is closed in GitHub; the live baseline evidence and the full performance-budget and bottleneck package are now attached.
- #830 production-hardening gate is complete and closed in GitHub; it is backed by [docs/status/PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md).
- #831 security red-team campaign is complete and closed in GitHub; it is backed by [docs/security/THREAT-MODEL-2026-04-19.md](../security/THREAT-MODEL-2026-04-19.md) and [docs/SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md).
- #832 CTO strategic reset is complete and closed in GitHub; it is backed by [docs/status/CTO-STRATEGIC-RESET-APRIL-19-2026.md](CTO-STRATEGIC-RESET-APRIL-19-2026.md).

### Recently closed

- #826 architecture stress review is complete and closed in GitHub; it is backed by [docs/status/ARCHITECTURE-STRESS-REVIEW-APRIL-19-2026.md](../../docs/status/ARCHITECTURE-STRESS-REVIEW-APRIL-19-2026.md).
- #822 design survivability review is complete and closed in GitHub; it is backed by [docs/status/SURVIVABILITY-REVIEW-APRIL-19-2026.md](../../docs/status/SURVIVABILITY-REVIEW-APRIL-19-2026.md).

## Governance Notes

- Use GitHub issues as the SSOT for active work.
- Before creating a new issue, search existing issues and this tracker first.
- Keep audit artifacts as evidence only; do not duplicate the same workstream across multiple docs.
- When work is completed, update the linked issue with validation evidence and close it only after the change is merged and deployed.
