# Code Quality and CI/CD Audit - April 19, 2026

Status: Active
Scope: Ranked quality teardown, CI/CD reproducibility audit, flake elimination, artifact integrity, and release-speed review.

## Purpose

This document is the canonical audit artifact for #823 and #827. It turns the current repository evidence into a ranked register with owners, remediation sequencing, and a test-gap matrix.

## Program Charter

This audit is the control surface for CI/CD reproducibility, flake elimination, artifact integrity, and release speed.

The program is fail-closed: if a required gate becomes advisory, the release path is treated as non-compliant until the strict path is restored or the exception is time-bounded.

## Failure Taxonomy

| Failure Class | Symptoms | Root Cause Pattern | Control |
| --- | --- | --- | --- |
| Reproducibility drift | Same change produces different pipeline outputs. | Unpinned toolchain versions, local-state dependencies, or non-hermetic inputs. | Require pinned inputs and deterministic wrappers for release gates. |
| Flake leakage | Tests pass locally but skip or fail inconsistently in CI. | Missing seeded state, environment coupling, or hidden assumptions. | Make required test fixtures explicit and visible in the gate output. |
| Artifact integrity drift | Build or validation artifacts differ from the tracked evidence. | Mutable bundles, missing manifests, or detached validation reports. | Keep hashes, manifests, and reports linked to the release record. |
| Release-speed regression | Promotion takes longer or requires manual intervention. | Fragmented checks, duplicate setup, or unclear rollback paths. | Use a single release wrapper and keep rollback steps scripted. |

## Release-Speed Objectives

| Objective | Target | Measurement |
| --- | --- | --- |
| Gate execution time | Keep the required release gate within one predictable operator session. | End-to-end run time from wrapper start to release decision. |
| Manual intervention | Minimize manual setup to exception handling only. | Count of operator prompts or ad hoc environment steps. |
| Retry cost | Reduce retries caused by missing state or unclear preconditions. | Number of reruns needed to obtain a trustworthy signal. |
| Evidence completeness | Every release decision has a reproducible artifact trail. | Presence of manifest, report, and linked issue comment. |

## Evidence Reviewed

- Shared libraries and canonical script surface: [../SHARED-LIBRARIES.md](../SHARED-LIBRARIES.md)
- Error-handling consistency gate: [../../scripts/ci/check-error-handling-consistency.sh](../../scripts/ci/check-error-handling-consistency.sh)
- Image immutability gate: [../../scripts/ci/check-image-immutability.sh](../../scripts/ci/check-image-immutability.sh)
- Terraform backend hardening gate: [../../scripts/ci/check-terraform-backend-hardening.sh](../../scripts/ci/check-terraform-backend-hardening.sh)
- Playwright evidence bundle: [../../tests/artifacts/playwright-results.json](../../tests/artifacts/playwright-results.json)
- Existing code-quality and security gate analysis: [QUALITY-GATE-FAILURE-ANALYSIS.md](QUALITY-GATE-FAILURE-ANALYSIS.md)

## Ranked Defect Register

| Rank | Severity | Area | Finding | Evidence | Owner | Remediation Sequence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | High | Test coverage | Authenticated E2E coverage is now wired into the CI validation workflow through a secret-backed storage-state decode path on push events, but the PR path still uses the unauthenticated smoke suite. | `.github/workflows/ci-validate.yml` now includes an authenticated E2E job that decodes `PLAYWRIGHT_STORAGE_STATE_B64` and runs the seeded Playwright flow. | QA / Platform | Keep the seeded gate on the release path, preserve the smoke suite as a regression guard, and decide whether PRs should gain a safe non-secret seed path later. |
| 2 | High | CI gating | Error-handling consistency is now enforced in the CI validation workflow, while direct local invocation remains advisory unless strict mode is requested. | `scripts/ci/check-error-handling-consistency.sh` exits 0 unless `--strict` is used, and `.github/workflows/ci-validate.yml` now passes `--strict`. | Platform / CI | Keep strict mode in the release gate, keep advisory mode only for local triage, and surface warnings as release blockers. |
| 3 | Medium | Legacy debt | The deprecated `scripts/common-functions.sh` shim still exists and must not attract new dependencies. | Documented as deprecated compatibility surface in `docs/SHARED-LIBRARIES.md`. | Platform | Freeze the shim, migrate remaining consumers to `scripts/_common/init.sh`, and block new usages in review. |
| 4 | Medium | Reproducibility | Some current validation paths still depend on local state or manual preconditions such as VPN access and authenticated storage state. | Playwright and live validation evidence require environment-specific setup. | QA / Operations | Standardize seeded test profiles and make the preconditions explicit in the gate so the result is reproducible across runs. |
| 5 | Low | SSOT hygiene | Multiple status and roadmap artifacts exist, but the precedence model is now explicit and needs disciplined maintenance. | Status index and roadmap docs already exist. | Program Owner | Keep the status index as the only navigation layer and avoid creating parallel summaries. |

## CI/CD Audit Register

| Area | Current Finding | Risk Level | What Good Looks Like |
| --- | --- | --- | --- |
| Reproducibility | CI validators exist, but some checks are still advisory or require local environment state. | Medium | Release-gate checks should fail closed with documented inputs and deterministic outputs. |
| Flake elimination | The authenticated Playwright gate now decodes a seeded storage state in CI on push events, while the unauthenticated smoke suite remains available for PRs and local triage. | Medium | Required state should be seeded for the release gate, and any skips should be explicit rather than silent. |
| Artifact integrity | Governance and policy validators are in place, and the current audit surface has hash-based evidence for key bundles. | Low | Artifact hashes, manifests, and validation reports should remain linked to the issue and PR trail. |
| Release speed | Validation coverage is solid, but manual environment setup and selective skips still slow repeatable execution. | Medium | A single release-gate wrapper should run the required checks with consistent inputs and minimal operator intervention. |

## Formal Refactor Backlog

1. Promote the strict variant of the error-handling consistency check into the release path.
2. Turn the authenticated Playwright flow into a required gate with seeded storage state.
3. Migrate any remaining legacy shell consumers to the canonical `scripts/_common/init.sh` stack.
4. Keep the current governance and CI validators as the stable integrity layer.
5. Keep status and roadmap documents indexed through the status SSOT only.

## Test-Gap Matrix

| Critical Flow | Current Gap | Evidence | Next Test |
| --- | --- | --- | --- |
| Portal auth | Authenticated storage-state coverage is still missing in the current evidence bundle. | `tests/artifacts/playwright-results.json` | Run the portal flow with seeded storage state and require the result in the gate. |
| IDE auth | Same authenticated-state gap as portal auth; the main CI workflow now has a seeded authenticated job on push, but the PR path remains unauthenticated. | `.github/workflows/ci-validate.yml` | Run the IDE flow with seeded storage state on the required release path and verify no redirect loop. |
| CI gate strictness | Direct invocation is advisory, but the CI validation gate now runs the check in strict mode. | `scripts/ci/check-error-handling-consistency.sh` and `.github/workflows/ci-validate.yml` | Keep the workflow strict and leave advisory mode only for local triage. |
| Artifact validation | Already covered by bundle and governance validators. | Existing security and policy reports | Keep current coverage as a non-regressing guard. |
| Release evidence | Repeatable release-speed evidence still depends on manual setup. | Existing CI/docs evidence | Add a single release wrapper that captures the same evidence every run. |

## Closure Criteria

- Authenticated E2E coverage runs with seeded state and no hidden skips in the required gate.
- CI audit findings are tracked to concrete fixes or explicit accepted risks with expiry.
- Legacy compatibility shims remain frozen and do not gain new dependencies.
- Release gating is reproducible and uses the same canonical evidence every run.

## Cross-References

- Status index: [README.md](README.md)
- Strategic reset: [CTO-STRATEGIC-RESET-APRIL-19-2026.md](CTO-STRATEGIC-RESET-APRIL-19-2026.md)
- Production hardening gate: [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
